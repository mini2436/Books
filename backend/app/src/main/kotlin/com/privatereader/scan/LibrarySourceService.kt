package com.privatereader.scan

import com.privatereader.books.BookService
import com.privatereader.books.CreateLibrarySourceRequest
import com.privatereader.books.LibrarySourceView
import com.privatereader.books.UpdateLibrarySourceRequest
import com.privatereader.common.toSqlTimestamp
import com.privatereader.config.AppProperties
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Service
import java.io.StringReader
import java.net.URI
import java.net.URLDecoder
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.time.Duration
import java.time.Instant
import java.util.Base64
import java.util.HexFormat
import javax.xml.XMLConstants
import javax.xml.parsers.DocumentBuilderFactory
import org.xml.sax.InputSource

@Service
class LibrarySourceService(
    private val jdbcClient: JdbcClient,
    private val bookService: BookService,
    private val appProperties: AppProperties,
) {
    private val httpClient: HttpClient = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(20))
        .followRedirects(HttpClient.Redirect.NORMAL)
        .build()

    fun createSource(request: CreateLibrarySourceRequest): LibrarySourceView {
        val normalized = request.toNormalized()
        val now = Instant.now()
        // 新增图书扫描源配置，并返回新建扫描源 ID。
        val id = jdbcClient.sql(
            """
            insert into library_sources (
                name, root_path, enabled, source_type, base_url, remote_path,
                username, password, scan_interval_minutes, created_at, updated_at
            ) values (
                :name, :rootPath, :enabled, :sourceType, :baseUrl, :remotePath,
                :username, :password, :scanIntervalMinutes, :now, :now
            )
            returning id
            """.trimIndent(),
        )
            .param("name", normalized.name)
            .param("rootPath", normalized.rootPath)
            .param("enabled", normalized.enabled)
            .param("sourceType", normalized.sourceType.name)
            .param("baseUrl", normalized.baseUrl)
            .param("remotePath", normalized.remotePath)
            .param("username", normalized.username)
            .param("password", normalized.password)
            .param("scanIntervalMinutes", normalized.scanIntervalMinutes)
            .param("now", now.toSqlTimestamp())
            .query(Long::class.java)
            .single()
        return getSourceView(id)
    }

    fun updateSource(sourceId: Long, request: UpdateLibrarySourceRequest): LibrarySourceView {
        val normalized = request.toNormalized()
        // 更新指定扫描源的路径、认证信息、启用状态和扫描间隔。
        val updated = jdbcClient.sql(
            """
            update library_sources
            set name = :name,
                root_path = :rootPath,
                enabled = :enabled,
                source_type = :sourceType,
                base_url = :baseUrl,
                remote_path = :remotePath,
                username = :username,
                password = :password,
                scan_interval_minutes = :scanIntervalMinutes,
                updated_at = :updatedAt
            where id = :sourceId
            """.trimIndent(),
        )
            .param("name", normalized.name)
            .param("rootPath", normalized.rootPath)
            .param("enabled", normalized.enabled)
            .param("sourceType", normalized.sourceType.name)
            .param("baseUrl", normalized.baseUrl)
            .param("remotePath", normalized.remotePath)
            .param("username", normalized.username)
            .param("password", normalized.password)
            .param("scanIntervalMinutes", normalized.scanIntervalMinutes)
            .param("updatedAt", Instant.now().toSqlTimestamp())
            .param("sourceId", sourceId)
            .update()
        require(updated > 0) { "Source $sourceId was not found" }
        return getSourceView(sourceId)
    }

    fun listSources(): List<LibrarySourceView> =
        // 查询全部扫描源配置，供后台扫描源管理页面展示。
        jdbcClient.sql(
            """
            select id, name, root_path, enabled, source_type, base_url, remote_path,
                   username, password, scan_interval_minutes, last_scan_at
            from library_sources
            order by id asc
            """.trimIndent(),
        )
            .query { rs, _ -> rs.toLibrarySourceView() }
            .list()

    fun scanSource(sourceId: Long): Map<String, Any> {
        val source = getSourceRecord(sourceId)
        val scanStartedAt = Instant.now()
        return try {
            val result = when (source.sourceType) {
                SourceType.WATCHED_FOLDER -> scanWatchedFolder(source)
                SourceType.WEBDAV -> scanWebDav(source)
            }
            touchLastScan(source.id, scanStartedAt)
            mapOf(
                "sourceId" to source.id,
                "imported" to result.imported,
                "missingMarked" to result.missingMarked,
            )
        } catch (exception: Exception) {
            touchLastScan(source.id, scanStartedAt)
            throw exception
        }
    }

    @Scheduled(fixedDelayString = "\${app.scheduler.library-source-poll-ms:300000}")
    fun scanAllEnabledSources() {
        val now = Instant.now()
        listSourceRecords()
            .filter { it.enabled }
            .filter { shouldScan(it, now) }
            .forEach { source ->
                runCatching { scanSource(source.id) }
            }
    }

    private fun scanWatchedFolder(source: SourceRecord): ScanResult {
        val rootPath = source.rootPath?.let(Path::of)
            ?: throw IllegalArgumentException("Watched folder path is missing")
        require(Files.exists(rootPath)) { "Source path does not exist" }

        val seenPaths = mutableSetOf<String>()
        var imported = 0
        Files.walk(rootPath).use { paths ->
            paths.filter { Files.isRegularFile(it) }
                .forEach { path ->
                    val normalized = path.toAbsolutePath().toString()
                    seenPaths += normalized
                    imported += tryImportFile(
                        filePath = path,
                        sourceType = SourceType.WATCHED_FOLDER,
                        sourceId = source.id,
                        sourcePath = normalized,
                    )
                }
        }
        return finalizeScan(source.id, seenPaths, imported)
    }

    private fun scanWebDav(source: SourceRecord): ScanResult {
        val rootUri = buildWebDavRootUri(source)
        val remoteFiles = collectWebDavFiles(source, rootUri)
        val seenPaths = mutableSetOf<String>()
        var imported = 0
        remoteFiles.forEach { remoteFile ->
            seenPaths += remoteFile.sourcePath
            val localFile = downloadWebDavFile(source, remoteFile)
            imported += tryImportFile(
                filePath = localFile,
                sourceType = SourceType.WEBDAV,
                sourceId = source.id,
                sourcePath = remoteFile.sourcePath,
            )
        }
        return finalizeScan(source.id, seenPaths, imported)
    }

    private fun tryImportFile(
        filePath: Path,
        sourceType: SourceType,
        sourceId: Long,
        sourcePath: String,
    ): Int =
        try {
            bookService.importDiscoveredFile(
                filePath = filePath,
                sourceType = sourceType.name,
                sourceId = sourceId,
                actorId = null,
                sourcePathOverride = sourcePath,
            )
            1
        } catch (_: IllegalArgumentException) {
            0
        }

    private fun finalizeScan(sourceId: Long, seenPaths: Set<String>, imported: Int): ScanResult {
        val tracked = bookService.listTrackedSourcePaths(sourceId).toSet()
        val missingPaths = tracked - seenPaths
        missingPaths.forEach { missingPath ->
            bookService.markMissingSourcePath(sourceId, missingPath)
        }
        return ScanResult(imported = imported, missingMarked = missingPaths.size)
    }

    private fun shouldScan(source: SourceRecord, now: Instant): Boolean {
        val lastScanAt = source.lastScanAt ?: return true
        return lastScanAt.plusSeconds(source.scanIntervalMinutes.toLong() * 60) <= now
    }

    private fun getSourceView(sourceId: Long): LibrarySourceView = getSourceRecord(sourceId).toLibrarySourceView()

    private fun getSourceRecord(sourceId: Long): SourceRecord =
        // 按扫描源 ID 查询完整配置，用于执行扫描或更新后回显。
        jdbcClient.sql(
            """
            select id, name, root_path, enabled, source_type, base_url, remote_path,
                   username, password, scan_interval_minutes, last_scan_at
            from library_sources
            where id = :sourceId
            """.trimIndent(),
        )
            .param("sourceId", sourceId)
            .query { rs, _ -> rs.toSourceRecord() }
            .optional()
            .orElseThrow { IllegalArgumentException("Source $sourceId was not found") }

    private fun listSourceRecords(): List<SourceRecord> =
        // 查询全部扫描源完整配置，供定时任务筛选需要执行的扫描源。
        jdbcClient.sql(
            """
            select id, name, root_path, enabled, source_type, base_url, remote_path,
                   username, password, scan_interval_minutes, last_scan_at
            from library_sources
            order by id asc
            """.trimIndent(),
        )
            .query { rs, _ -> rs.toSourceRecord() }
            .list()

    private fun touchLastScan(sourceId: Long, scannedAt: Instant) {
        // 记录指定扫描源最近一次扫描时间，用于定时轮询间隔判断。
        jdbcClient.sql(
            """
            update library_sources
            set last_scan_at = :lastScanAt,
                updated_at = :updatedAt
            where id = :sourceId
            """.trimIndent(),
        )
            .param("lastScanAt", scannedAt.toSqlTimestamp())
            .param("updatedAt", Instant.now().toSqlTimestamp())
            .param("sourceId", sourceId)
            .update()
    }

    private fun buildWebDavRootUri(source: SourceRecord): URI {
        val baseUrl = source.baseUrl ?: throw IllegalArgumentException("WebDAV address is missing")
        val baseUri = URI.create(if (baseUrl.endsWith("/")) baseUrl else "$baseUrl/")
        val normalizedRemotePath = normalizeRemotePath(source.remotePath)
        return if (normalizedRemotePath == "/") {
            baseUri
        } else {
            val relativePath = normalizedRemotePath.trimStart('/').let {
                if (it.endsWith("/")) it else "$it/"
            }
            baseUri.resolve(relativePath)
        }
    }

    private fun collectWebDavFiles(source: SourceRecord, directoryUri: URI): List<WebDavFile> {
        val response = httpClient.send(
            webDavRequest(
                uri = directoryUri,
                method = "PROPFIND",
                depth = "1",
                body = """
                <d:propfind xmlns:d="DAV:">
                  <d:prop>
                    <d:resourcetype />
                  </d:prop>
                </d:propfind>
                """.trimIndent(),
                source = source,
            ),
            HttpResponse.BodyHandlers.ofString(),
        )
        require(response.statusCode() in setOf(200, 207)) {
            "WebDAV PROPFIND failed with status ${response.statusCode()}"
        }

        val documentBuilderFactory = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = true
            setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
            setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
        }
        val document = documentBuilderFactory.newDocumentBuilder()
            .parse(InputSource(StringReader(response.body())))

        val currentDirectory = normalizeHref(decodeHref(directoryUri.path))
        val responses = document.getElementsByTagNameNS("*", "response")
        val files = mutableListOf<WebDavFile>()
        for (index in 0 until responses.length) {
            val node = responses.item(index)
            val href = node.childNodes.toNodeList()
                .firstOrNull { it.localName == "href" }
                ?.textContent
                ?.trim()
                ?.takeIf(String::isNotEmpty)
                ?: continue
            val resolvedUri = directoryUri.resolve(href)
            val normalizedPath = normalizeHref(decodeHref(resolvedUri.path))
            if (normalizedPath == currentDirectory) {
                continue
            }

            val isCollection = node.childNodes.toNodeList().any { child ->
                child.localName == "propstat" && child.childNodes.toNodeList().any { propstatChild ->
                    propstatChild.localName == "prop" && propstatChild.childNodes.toNodeList().any { propChild ->
                        propChild.localName == "resourcetype" &&
                            propChild.childNodes.toNodeList().any { it.localName == "collection" }
                    }
                }
            }

            if (isCollection) {
                files += collectWebDavFiles(source, ensureDirectoryUri(resolvedUri))
                continue
            }

            files += WebDavFile(
                uri = resolvedUri,
                sourcePath = normalizedPath,
            )
        }
        return files
    }

    private fun downloadWebDavFile(source: SourceRecord, remoteFile: WebDavFile): Path {
        val extension = remoteFile.sourcePath.substringAfterLast('.', "")
        val fileName = buildString {
            append(hashString(remoteFile.sourcePath))
            if (extension.isNotEmpty()) {
                append('.')
                append(extension.lowercase())
            }
        }
        val cacheDir = Path.of(appProperties.storageRoot, "library-source-cache", "source-${source.id}")
        Files.createDirectories(cacheDir)
        val targetFile = cacheDir.resolve(fileName)

        val response = httpClient.send(
            webDavRequest(
                uri = remoteFile.uri,
                method = "GET",
                depth = null,
                body = null,
                source = source,
            ),
            HttpResponse.BodyHandlers.ofInputStream(),
        )
        require(response.statusCode() in 200..299) {
            "WebDAV download failed with status ${response.statusCode()}"
        }
        response.body().use { body ->
            Files.copy(body, targetFile, java.nio.file.StandardCopyOption.REPLACE_EXISTING)
        }
        return targetFile
    }

    private fun webDavRequest(
        uri: URI,
        method: String,
        depth: String?,
        body: String?,
        source: SourceRecord,
    ): HttpRequest {
        val builder = HttpRequest.newBuilder(uri)
            .timeout(Duration.ofMinutes(2))
            .header("Accept", "application/xml,text/xml,*/*")
            .method(
                method,
                if (body == null) {
                    HttpRequest.BodyPublishers.noBody()
                } else {
                    HttpRequest.BodyPublishers.ofString(body)
                },
            )
        if (depth != null) {
            builder.header("Depth", depth)
        }
        if (body != null) {
            builder.header("Content-Type", "application/xml; charset=utf-8")
        }
        buildBasicAuthHeader(source.username, source.password)?.let {
            builder.header("Authorization", it)
        }
        return builder.build()
    }

    private fun buildBasicAuthHeader(username: String?, password: String?): String? {
        val normalizedUsername = username?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val credentials = "$normalizedUsername:${password.orEmpty()}"
        val encoded = Base64.getEncoder().encodeToString(credentials.toByteArray(StandardCharsets.UTF_8))
        return "Basic $encoded"
    }

    private fun hashString(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        return HexFormat.of().formatHex(digest.digest(value.toByteArray(StandardCharsets.UTF_8)))
    }

    private fun normalizeRemotePath(value: String?): String {
        val raw = value?.trim().orEmpty()
        if (raw.isEmpty() || raw == "/") {
            return "/"
        }
        val normalized = raw.replace('\\', '/').trim('/')
        return "/$normalized"
    }

    private fun normalizeHref(value: String): String {
        if (value.isBlank()) {
            return "/"
        }
        val normalized = value.replace('\\', '/')
        return if (normalized.endsWith("/")) normalized.dropLast(1) else normalized
    }

    private fun decodeHref(value: String): String = URLDecoder.decode(value, StandardCharsets.UTF_8)

    private fun ensureDirectoryUri(uri: URI): URI = if (uri.path.endsWith("/")) uri else URI.create("$uri/")

    private fun org.w3c.dom.NodeList.toNodeList(): List<org.w3c.dom.Node> =
        (0 until length).map(::item)

    private fun java.sql.ResultSet.toSourceRecord(): SourceRecord =
        SourceRecord(
            id = getLong("id"),
            name = getString("name"),
            sourceType = SourceType.fromValue(getString("source_type")),
            rootPath = getString("root_path"),
            baseUrl = getString("base_url"),
            remotePath = getString("remote_path"),
            username = getString("username"),
            password = getString("password"),
            enabled = getBoolean("enabled"),
            scanIntervalMinutes = getInt("scan_interval_minutes"),
            lastScanAt = getTimestamp("last_scan_at")?.toInstant(),
        )

    private fun java.sql.ResultSet.toLibrarySourceView(): LibrarySourceView = toSourceRecord().toLibrarySourceView()

    private fun SourceRecord.toLibrarySourceView(): LibrarySourceView =
        LibrarySourceView(
            id = id,
            name = name,
            sourceType = sourceType.name,
            rootPath = rootPath.takeIf { sourceType == SourceType.WATCHED_FOLDER },
            baseUrl = baseUrl,
            remotePath = remotePath,
            username = username,
            password = password,
            enabled = enabled,
            scanIntervalMinutes = scanIntervalMinutes,
            lastScanAt = lastScanAt?.toString(),
        )

    private fun CreateLibrarySourceRequest.toNormalized(): NormalizedSourceRequest =
        NormalizedSourceRequest.from(
            name = name,
            sourceType = sourceType,
            rootPath = rootPath,
            baseUrl = baseUrl,
            remotePath = remotePath,
            username = username,
            password = password,
            enabled = enabled,
            scanIntervalMinutes = scanIntervalMinutes,
        )

    private fun UpdateLibrarySourceRequest.toNormalized(): NormalizedSourceRequest =
        NormalizedSourceRequest.from(
            name = name,
            sourceType = sourceType,
            rootPath = rootPath,
            baseUrl = baseUrl,
            remotePath = remotePath,
            username = username,
            password = password,
            enabled = enabled,
            scanIntervalMinutes = scanIntervalMinutes,
        )

    private data class SourceRecord(
        val id: Long,
        val name: String,
        val sourceType: SourceType,
        val rootPath: String?,
        val baseUrl: String?,
        val remotePath: String?,
        val username: String?,
        val password: String?,
        val enabled: Boolean,
        val scanIntervalMinutes: Int,
        val lastScanAt: Instant?,
    )

    private data class ScanResult(
        val imported: Int,
        val missingMarked: Int,
    )

    private data class WebDavFile(
        val uri: URI,
        val sourcePath: String,
    )

    private data class NormalizedSourceRequest(
        val name: String,
        val sourceType: SourceType,
        val rootPath: String,
        val baseUrl: String?,
        val remotePath: String?,
        val username: String?,
        val password: String?,
        val enabled: Boolean,
        val scanIntervalMinutes: Int,
    ) {
        companion object {
            fun from(
                name: String,
                sourceType: String,
                rootPath: String?,
                baseUrl: String?,
                remotePath: String?,
                username: String?,
                password: String?,
                enabled: Boolean,
                scanIntervalMinutes: Int,
            ): NormalizedSourceRequest {
                require(scanIntervalMinutes > 0) { "Scan interval must be greater than 0" }
                val normalizedName = name.trim()
                require(normalizedName.isNotEmpty()) { "Source name must not be blank" }
                val type = SourceType.fromValue(sourceType)
                return when (type) {
                    SourceType.WATCHED_FOLDER -> {
                        val normalizedRootPath = rootPath?.trim()?.takeIf { it.isNotEmpty() }
                            ?: throw IllegalArgumentException("Watched folder path is required")
                        NormalizedSourceRequest(
                            name = normalizedName,
                            sourceType = type,
                            rootPath = normalizedRootPath,
                            baseUrl = null,
                            remotePath = null,
                            username = null,
                            password = null,
                            enabled = enabled,
                            scanIntervalMinutes = scanIntervalMinutes,
                        )
                    }

                    SourceType.WEBDAV -> {
                        val normalizedBaseUrl = baseUrl?.trim()?.takeIf { it.isNotEmpty() }
                            ?: throw IllegalArgumentException("WebDAV address is required")
                        val normalizedRemotePath = if (remotePath.isNullOrBlank()) "/" else remotePath.trim()
                        NormalizedSourceRequest(
                            name = normalizedName,
                            sourceType = type,
                            rootPath = normalizeRemotePathStatic(normalizedRemotePath),
                            baseUrl = normalizedBaseUrl,
                            remotePath = normalizeRemotePathStatic(normalizedRemotePath),
                            username = username?.trim()?.takeIf { it.isNotEmpty() },
                            password = password?.takeIf { it.isNotEmpty() },
                            enabled = enabled,
                            scanIntervalMinutes = scanIntervalMinutes,
                        )
                    }
                }
            }

            private fun normalizeRemotePathStatic(value: String): String {
                val raw = value.trim()
                if (raw.isEmpty() || raw == "/") {
                    return "/"
                }
                return "/${raw.replace('\\', '/').trim('/')}"
            }
        }
    }

    private enum class SourceType {
        WATCHED_FOLDER,
        WEBDAV,
        ;

        companion object {
            fun fromValue(value: String): SourceType =
                entries.firstOrNull { it.name == value.trim().uppercase() }
                    ?: throw IllegalArgumentException("Unsupported source type: $value")
        }
    }
}
