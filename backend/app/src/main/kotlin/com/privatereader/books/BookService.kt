package com.privatereader.books

import com.fasterxml.jackson.core.type.TypeReference
import com.fasterxml.jackson.databind.ObjectMapper
import com.privatereader.auth.AuthRepository
import com.privatereader.auth.UserPrincipal
import com.privatereader.common.toSqlTimestamp
import com.privatereader.config.AppProperties
import com.privatereader.pluginruntime.PluginRegistryService
import org.springframework.core.io.ByteArrayResource
import org.springframework.core.io.FileSystemResource
import org.springframework.http.MediaType
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.multipart.MultipartFile
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.sql.ResultSet
import java.time.Instant
import java.util.HexFormat
import java.util.UUID

@Service
class BookService(
    private val jdbcClient: JdbcClient,
    private val pluginRegistryService: PluginRegistryService,
    private val objectMapper: ObjectMapper,
    private val appProperties: AppProperties,
    private val authRepository: AuthRepository,
) {
    fun uploadBook(file: MultipartFile, actor: UserPrincipal): BookDetailView {
        require(!file.isEmpty) { "Uploaded file must not be empty" }
        val uploadsDir = Path.of(appProperties.storageRoot, "uploads")
        Files.createDirectories(uploadsDir)
        val originalFilename = Path.of(file.originalFilename ?: "book-${UUID.randomUUID()}").fileName.toString()
        val targetDir = uploadsDir.resolve(UUID.randomUUID().toString())
        Files.createDirectories(targetDir)
        val target = targetDir.resolve(originalFilename)
        file.inputStream.use { input ->
            Files.copy(input, target, StandardCopyOption.REPLACE_EXISTING)
        }
        return importDiscoveredFile(target, "MANAGED_UPLOAD", null, actor.id)
    }

    @Transactional
    fun importDiscoveredFile(filePath: Path, sourceType: String, sourceId: Long?, actorId: Long?): BookDetailView {
        // Import flow is format-driven: detect the compile-time plugin first, then persist
        // the canonical book record, file source metadata, and the reader manifest/index excerpt.
        val plugin = pluginRegistryService.findPluginFor(filePath.fileName.toString())
            ?: throw IllegalArgumentException("No plugin available for file ${filePath.fileName}")
        val fileHash = sha256(filePath)
        val preparedImport = prepareImport(filePath, plugin)
        val existing = findBookByHash(fileHash)
        if (existing != null) {
            // A repeated NAS scan should revive an existing source path instead of creating duplicates.
            refreshExistingFileReference(existing.fileId, filePath, sourceType, sourceId, preparedImport.format)
            reconcileExistingImport(existing.bookId, filePath, preparedImport)
            insertImportJob(existing.bookId, sourceId, existing.fileId, "Reused existing import from ${plugin.pluginId}")
            if (actorId != null) {
                grantBook(existing.bookId, actorId, actorId)
            }
            return getBookDetail(existing.bookId)
        }

        val now = Instant.now()
        val bookId = jdbcClient.sql(
            """
            insert into books (title, author, description, created_at, updated_at)
            values (:title, :author, :description, :now, :now)
            returning id
            """.trimIndent(),
        )
            .param("title", preparedImport.metadata.title)
            .param("author", preparedImport.metadata.author)
            .param("description", preparedImport.metadata.description)
            .param("now", now.toSqlTimestamp())
            .query(Long::class.java)
            .single()

        val fileId = jdbcClient.sql(
            """
            insert into book_files (
                book_id, plugin_id, file_hash, storage_path, source_type, source_id, source_path,
                format, file_size, source_missing, created_at, updated_at
            ) values (
                :bookId, :pluginId, :fileHash, :storagePath, :sourceType, :sourceId, :sourcePath,
                :format, :fileSize, false, :now, :now
            )
            returning id
            """.trimIndent(),
        )
            .param("bookId", bookId)
            .param("pluginId", plugin.pluginId)
            .param("fileHash", fileHash)
            .param("storagePath", filePath.toAbsolutePath().toString())
            .param("sourceType", sourceType)
            .param("sourceId", sourceId)
            .param("sourcePath", filePath.toAbsolutePath().toString())
            .param("format", preparedImport.format)
            .param("fileSize", Files.size(filePath))
            .param("now", now.toSqlTimestamp())
            .query(Long::class.java)
            .single()

        upsertBookFormat(bookId, preparedImport)
        insertImportJob(bookId, sourceId, fileId, "Imported by ${plugin.pluginId}")

        if (actorId != null) {
            grantBook(bookId, actorId, actorId)
        }

        return getBookDetail(bookId)
    }

    fun listAccessibleBooks(userId: Long): List<BookView> {
        if (hasGlobalLibraryAccess(userId)) {
            return jdbcClient.sql(
                """
                select b.id, b.title, b.author, b.description, bf.plugin_id, bf.format, bf.source_type, bf.source_missing, b.updated_at
                from books b
                join book_files bf on bf.book_id = b.id
                where bf.id = (
                    select max(inner_bf.id) from book_files inner_bf
                    where inner_bf.book_id = b.id
                )
                order by b.updated_at desc, b.id desc
                """.trimIndent(),
            )
                .query { rs, _ -> rs.toBookView(granted = true) }
                .list()
        }

        return jdbcClient.sql(
            """
            select b.id, b.title, b.author, b.description, bf.plugin_id, bf.format, bf.source_type, bf.source_missing, b.updated_at
            from books b
            join book_files bf on bf.book_id = b.id
            join user_book_access uba on uba.book_id = b.id and uba.user_id = :userId
            order by b.updated_at desc
            """.trimIndent(),
        )
            .param("userId", userId)
            .query { rs, _ -> rs.toBookView(granted = true) }
            .list()
    }

    fun listAdminBooks(): List<AdminBookView> =
        jdbcClient.sql(
            """
            select b.id, b.title, b.author, b.description, bf.plugin_id, bf.format, bf.source_type, bf.source_missing, b.updated_at
            from books b
            join book_files bf on bf.book_id = b.id
            where bf.id = (
                select max(inner_bf.id) from book_files inner_bf
                where inner_bf.book_id = b.id
            )
            order by b.updated_at desc, b.id desc
            """.trimIndent(),
        )
            .query { rs, _ ->
                AdminBookView(
                    id = rs.getLong("id"),
                    title = rs.getString("title"),
                    author = rs.getString("author"),
                    description = rs.getString("description"),
                    pluginId = rs.getString("plugin_id"),
                    format = rs.getString("format"),
                    sourceType = rs.getString("source_type"),
                    sourceMissing = rs.getBoolean("source_missing"),
                    updatedAt = rs.getTimestamp("updated_at").toInstant().toString(),
                )
            }
            .list()

    fun getAccessibleBook(userId: Long, bookId: Long): BookDetailView {
        require(hasAccess(userId, bookId)) { "Book access denied" }
        return getBookDetail(bookId)
    }

    fun getContentManifest(userId: Long, bookId: Long): Map<String, Any>? {
        require(hasAccess(userId, bookId)) { "Book access denied" }
        return getBookDetail(bookId).manifest
    }

    fun getBookFile(userId: Long, bookId: Long): FileSystemResource {
        require(hasAccess(userId, bookId)) { "Book access denied" }
        return FileSystemResource(resolveBookFileRef(bookId).storagePath)
    }

    fun getBookCover(userId: Long, bookId: Long): BookCoverResource? {
        require(hasAccess(userId, bookId)) { "Book access denied" }
        val fileRef = resolveBookFileRef(bookId)
        val plugin = pluginRegistryService.findPluginById(fileRef.pluginId) ?: return null
        val cover = plugin.extractCover(Path.of(fileRef.storagePath)) ?: return null
        return BookCoverResource(
            mimeType = cover.mimeType,
            resource = ByteArrayResource(cover.bytes),
        )
    }

    fun resolveMediaType(bookId: Long): MediaType {
        val format = resolveBookFileRef(bookId).format
        return when (format.lowercase()) {
            "epub" -> MediaType("application", "epub+zip")
            "pdf" -> MediaType.APPLICATION_PDF
            "txt" -> MediaType.TEXT_PLAIN
            else -> MediaType.APPLICATION_OCTET_STREAM
        }
    }

    fun grantBook(bookId: Long, userId: Long, grantedBy: Long) {
        jdbcClient.sql(
            """
            insert into user_book_access (user_id, book_id, granted_by, granted_at)
            values (:userId, :bookId, :grantedBy, :grantedAt)
            on conflict (user_id, book_id) do update
            set granted_by = excluded.granted_by,
                granted_at = excluded.granted_at
            """.trimIndent(),
        )
            .param("userId", userId)
            .param("bookId", bookId)
            .param("grantedBy", grantedBy)
            .param("grantedAt", Instant.now().toSqlTimestamp())
            .update()
    }

    fun listTrackedSourcePaths(sourceId: Long): List<String> =
        jdbcClient.sql(
            """
            select source_path from book_files
            where source_id = :sourceId and source_type = 'WATCHED_FOLDER'
            """.trimIndent(),
        )
            .param("sourceId", sourceId)
            .query(String::class.java)
            .list()

    fun markMissingSourcePath(sourceId: Long, sourcePath: String) {
        jdbcClient.sql(
            """
            update book_files
            set source_missing = true, updated_at = :updatedAt
            where source_id = :sourceId and source_path = :sourcePath
            """.trimIndent(),
        )
            .param("sourceId", sourceId)
            .param("sourcePath", sourcePath)
            .param("updatedAt", Instant.now().toSqlTimestamp())
            .update()
    }

    fun listImportJobs(): List<Map<String, Any?>> =
        jdbcClient.sql(
            """
            select id, book_id, source_id, file_id, status, message, created_at, updated_at
            from import_jobs
            order by created_at desc
            limit 100
            """.trimIndent(),
        )
            .query { rs, _ ->
                mapOf(
                    "id" to rs.getLong("id"),
                    "bookId" to rs.getLong("book_id"),
                    "sourceId" to rs.getObject("source_id"),
                    "fileId" to rs.getLong("file_id"),
                    "status" to rs.getString("status"),
                    "message" to rs.getString("message"),
                    "createdAt" to rs.getTimestamp("created_at").toInstant().toString(),
                    "updatedAt" to rs.getTimestamp("updated_at").toInstant().toString(),
                )
            }
            .list()

    private fun hasAccess(userId: Long, bookId: Long): Boolean {
        if (hasGlobalLibraryAccess(userId)) {
            return true
        }
        return jdbcClient.sql(
            """
            select count(*) from user_book_access
            where user_id = :userId and book_id = :bookId
            """.trimIndent(),
        )
            .param("userId", userId)
            .param("bookId", bookId)
            .query(Long::class.java)
            .single() > 0
    }

    private fun hasGlobalLibraryAccess(userId: Long): Boolean =
        authRepository.findUserById(userId)?.role in setOf("SUPER_ADMIN", "LIBRARIAN")

    private fun ResultSet.toBookView(granted: Boolean): BookView =
        BookView(
            id = getLong("id"),
            title = getString("title"),
            author = getString("author"),
            description = getString("description"),
            pluginId = getString("plugin_id"),
            format = getString("format"),
            sourceType = getString("source_type"),
            granted = granted,
            sourceMissing = getBoolean("source_missing"),
            updatedAt = getTimestamp("updated_at").toInstant().toString(),
        )

    private fun getBookDetail(bookId: Long): BookDetailView =
        jdbcClient.sql(
            """
            select b.id, b.title, b.author, b.description, bf.plugin_id, bf.format, f.source_type, f.source_missing,
                   bf.manifest_json, bf.capabilities_json
            from books b
            join book_files f on f.book_id = b.id
            join book_formats bf on bf.book_id = b.id
            where b.id = :bookId
            order by f.id desc
            limit 1
            """.trimIndent(),
        )
            .param("bookId", bookId)
            .query { rs, _ -> rs.toBookDetailView() }
            .single()

    private fun ResultSet.toBookDetailView(): BookDetailView {
        val manifestJson = getString("manifest_json")
        // The manifest stays JSON in storage so every plugin can emit its own reader-specific
        // navigation structure without forcing a rigid relational schema.
        val manifest = manifestJson?.let {
            objectMapper.readValue(it, object : TypeReference<Map<String, Any>>() {})
        }
        val capabilities = objectMapper.readValue(getString("capabilities_json"), object : TypeReference<List<String>>() {})
        return BookDetailView(
            id = getLong("id"),
            title = getString("title"),
            author = getString("author"),
            description = getString("description"),
            pluginId = getString("plugin_id"),
            format = getString("format"),
            sourceType = getString("source_type"),
            manifest = manifest,
            capabilities = capabilities.toSet(),
            sourceMissing = getBoolean("source_missing"),
        )
    }

    private fun prepareImport(filePath: Path, plugin: com.privatereader.plugin.BookFormatPlugin): PreparedImport {
        val metadata = plugin.extractMetadata(filePath)
        val manifestJson = plugin.buildManifest(filePath)?.let { objectMapper.writeValueAsString(it) }
        val capabilitiesJson = objectMapper.writeValueAsString(plugin.capabilities.map { it.name })
        return PreparedImport(
            metadata = metadata,
            format = filePath.fileName.toString().substringAfterLast('.', "bin").lowercase(),
            pluginId = plugin.pluginId,
            capabilitiesJson = capabilitiesJson,
            manifestJson = manifestJson,
            onlineReadable = plugin.capabilities.any { it.name == "READ_ONLINE" },
            indexExcerpt = plugin.extractIndexableContent(filePath)?.text?.take(10_000),
        )
    }

    private fun refreshExistingFileReference(
        fileId: Long,
        filePath: Path,
        sourceType: String,
        sourceId: Long?,
        format: String,
    ) {
        jdbcClient.sql(
            """
            update book_files
            set storage_path = :storagePath,
                source_type = :sourceType,
                source_id = :sourceId,
                source_path = :sourcePath,
                format = :format,
                file_size = :fileSize,
                source_missing = false,
                updated_at = :updatedAt
            where id = :fileId
            """.trimIndent(),
        )
            .param("storagePath", filePath.toAbsolutePath().toString())
            .param("sourceType", sourceType)
            .param("sourceId", sourceId)
            .param("sourcePath", filePath.toAbsolutePath().toString())
            .param("format", format)
            .param("fileSize", Files.size(filePath))
            .param("updatedAt", Instant.now().toSqlTimestamp())
            .param("fileId", fileId)
            .update()
    }

    private fun reconcileExistingImport(bookId: Long, filePath: Path, preparedImport: PreparedImport) {
        jdbcClient.sql(
            """
            update books
            set title = :title,
                author = :author,
                description = :description,
                updated_at = :updatedAt
            where id = :bookId
            """.trimIndent(),
        )
            .param("title", preparedImport.metadata.title)
            .param("author", preparedImport.metadata.author)
            .param("description", preparedImport.metadata.description)
            .param("updatedAt", Instant.now().toSqlTimestamp())
            .param("bookId", bookId)
            .update()

        upsertBookFormat(bookId, preparedImport)
    }

    private fun upsertBookFormat(bookId: Long, preparedImport: PreparedImport) {
        val updated = jdbcClient.sql(
            """
            update book_formats
            set plugin_id = :pluginId,
                format = :format,
                capabilities_json = :capabilitiesJson,
                manifest_json = :manifestJson,
                online_readable = :onlineReadable,
                index_excerpt = :indexExcerpt,
                updated_at = :updatedAt
            where book_id = :bookId
            """.trimIndent(),
        )
            .param("pluginId", preparedImport.pluginId)
            .param("format", preparedImport.format)
            .param("capabilitiesJson", preparedImport.capabilitiesJson)
            .param("manifestJson", preparedImport.manifestJson)
            .param("onlineReadable", preparedImport.onlineReadable)
            .param("indexExcerpt", preparedImport.indexExcerpt)
            .param("updatedAt", Instant.now().toSqlTimestamp())
            .param("bookId", bookId)
            .update()

        if (updated > 0) {
            return
        }

        val now = Instant.now()
        jdbcClient.sql(
            """
            insert into book_formats (
                book_id, plugin_id, format, capabilities_json, manifest_json, online_readable, index_excerpt, created_at, updated_at
            ) values (
                :bookId, :pluginId, :format, :capabilitiesJson, :manifestJson, :onlineReadable, :indexExcerpt, :now, :now
            )
            """.trimIndent(),
        )
            .param("bookId", bookId)
            .param("pluginId", preparedImport.pluginId)
            .param("format", preparedImport.format)
            .param("capabilitiesJson", preparedImport.capabilitiesJson)
            .param("manifestJson", preparedImport.manifestJson)
            .param("onlineReadable", preparedImport.onlineReadable)
            .param("indexExcerpt", preparedImport.indexExcerpt)
            .param("now", now.toSqlTimestamp())
            .update()
    }

    private fun insertImportJob(bookId: Long, sourceId: Long?, fileId: Long, message: String) {
        val now = Instant.now()
        jdbcClient.sql(
            """
            insert into import_jobs (
                book_id, source_id, file_id, status, message, created_at, updated_at
            ) values (
                :bookId, :sourceId, :fileId, 'COMPLETED', :message, :now, :now
            )
            """.trimIndent(),
        )
            .param("bookId", bookId)
            .param("sourceId", sourceId)
            .param("fileId", fileId)
            .param("message", message)
            .param("now", now.toSqlTimestamp())
            .update()
    }

    private fun findBookByHash(hash: String): ExistingBookRef? =
        jdbcClient.sql(
            """
            select book_id, id from book_files
            where file_hash = :fileHash
            limit 1
            """.trimIndent(),
        )
            .param("fileHash", hash)
            .query { rs, _ -> ExistingBookRef(bookId = rs.getLong("book_id"), fileId = rs.getLong("id")) }
            .optional()
            .orElse(null)

    private fun resolveBookFileRef(bookId: Long): BookFileRef =
        jdbcClient.sql(
            """
            select storage_path, plugin_id, format from book_files
            where book_id = :bookId
            order by id desc
            limit 1
            """.trimIndent(),
        )
            .param("bookId", bookId)
            .query { rs, _ ->
                BookFileRef(
                    storagePath = rs.getString("storage_path"),
                    pluginId = rs.getString("plugin_id"),
                    format = rs.getString("format"),
                )
            }
            .single()

    private fun sha256(path: Path): String {
        val digest = MessageDigest.getInstance("SHA-256")
        Files.newInputStream(path).use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                digest.update(buffer, 0, read)
            }
        }
        return HexFormat.of().formatHex(digest.digest())
    }

    private data class ExistingBookRef(
        val bookId: Long,
        val fileId: Long,
    )

    data class BookCoverResource(
        val mimeType: String,
        val resource: ByteArrayResource,
    )

    private data class BookFileRef(
        val storagePath: String,
        val pluginId: String,
        val format: String,
    )

    private data class PreparedImport(
        val metadata: com.privatereader.plugin.BookMetadata,
        val format: String,
        val pluginId: String,
        val capabilitiesJson: String,
        val manifestJson: String?,
        val onlineReadable: Boolean,
        val indexExcerpt: String?,
    )
}
