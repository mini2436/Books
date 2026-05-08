package com.privatereader.books

import com.fasterxml.jackson.core.type.TypeReference
import com.fasterxml.jackson.databind.ObjectMapper
import com.privatereader.auth.AuthRepository
import com.privatereader.auth.UserPrincipal
import com.privatereader.common.toSqlTimestamp
import com.privatereader.config.AppProperties
import com.privatereader.plugin.StructuredBlockType
import com.privatereader.plugin.StructuredBookContent
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
    fun importDiscoveredFile(
        filePath: Path,
        sourceType: String,
        sourceId: Long?,
        actorId: Long?,
        sourcePathOverride: String? = null,
    ): BookDetailView {
        // Import flow is format-driven: detect the compile-time plugin first, then persist
        // the canonical book record, file source metadata, and the reader manifest/index excerpt.
        val plugin = pluginRegistryService.findPluginFor(filePath.fileName.toString())
            ?: throw IllegalArgumentException("No plugin available for file ${filePath.fileName}")
        val fileHash = sha256(filePath)
        val preparedImport = prepareImport(filePath, plugin)
        val existing = findBookByHash(fileHash)
        if (existing != null) {
            // A repeated NAS scan should revive an existing source path instead of creating duplicates.
            refreshExistingFileReference(
                existing.fileId,
                filePath,
                sourceType,
                sourceId,
                preparedImport.format,
                sourcePathOverride,
            )
            reconcileExistingImport(existing.bookId, filePath, preparedImport)
            refreshStructuredContent(existing.bookId, existing.fileId, fileHash, plugin.pluginId, filePath)
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
            .param("sourcePath", sourcePathOverride ?: filePath.toAbsolutePath().toString())
            .param("format", preparedImport.format)
            .param("fileSize", Files.size(filePath))
            .param("now", now.toSqlTimestamp())
            .query(Long::class.java)
            .single()

        upsertBookFormat(bookId, preparedImport)
        refreshStructuredContent(bookId, fileId, fileHash, plugin.pluginId, filePath)
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
            select b.id, b.title, b.author, b.group_name, b.description, bf.plugin_id, bf.format, bf.source_type, bf.source_missing, b.updated_at
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
                    groupName = rs.getString("group_name"),
                    description = rs.getString("description"),
                    pluginId = rs.getString("plugin_id"),
                    format = rs.getString("format"),
                    sourceType = rs.getString("source_type"),
                    sourceMissing = rs.getBoolean("source_missing"),
                    updatedAt = rs.getTimestamp("updated_at").toInstant().toString(),
                )
            }
            .list()

    fun getAdminBookDetail(bookId: Long): AdminBookDetailView =
        jdbcClient.sql(
            """
            select b.id, b.title, b.author, b.group_name, b.description, bf.plugin_id, bf.format, f.source_type, f.source_missing,
                   exists(
                       select 1 from book_content_versions bcv
                       where bcv.book_id = b.id and bcv.status = 'READY'
                   ) as has_structured_content,
                   (
                       select bcv.content_model from book_content_versions bcv
                       where bcv.book_id = b.id and bcv.status = 'READY'
                       order by bcv.id desc
                       limit 1
                   ) as content_model,
                   (
                       select bcv.id from book_content_versions bcv
                       where bcv.book_id = b.id and bcv.status = 'READY'
                       order by bcv.id desc
                       limit 1
                   ) as latest_content_version_id,
                   b.updated_at
            from books b
            join book_files f on f.book_id = b.id
            join book_formats bf on bf.book_id = b.id
            where b.id = :bookId
            order by f.id desc
            limit 1
            """.trimIndent(),
        )
            .param("bookId", bookId)
            .query { rs, _ ->
                AdminBookDetailView(
                    id = rs.getLong("id"),
                    title = rs.getString("title"),
                    author = rs.getString("author"),
                    groupName = rs.getString("group_name"),
                    description = rs.getString("description"),
                    pluginId = rs.getString("plugin_id"),
                    format = rs.getString("format"),
                    sourceType = rs.getString("source_type"),
                    sourceMissing = rs.getBoolean("source_missing"),
                    hasStructuredContent = rs.getBoolean("has_structured_content"),
                    contentModel = rs.getString("content_model"),
                    latestContentVersionId = rs.getObject("latest_content_version_id")?.let { (it as Number).toLong() },
                    updatedAt = rs.getTimestamp("updated_at").toInstant().toString(),
                )
            }
            .optional()
            .orElseThrow { IllegalArgumentException("Book $bookId was not found") }

    fun getAccessibleBook(userId: Long, bookId: Long): BookDetailView {
        require(hasAccess(userId, bookId)) { "Book access denied" }
        return getBookDetail(bookId)
    }

    fun getContentManifest(userId: Long, bookId: Long): Map<String, Any>? {
        require(hasAccess(userId, bookId)) { "Book access denied" }
        return getBookDetail(bookId).manifest
    }

    fun getStructuredContent(userId: Long, bookId: Long): BookContentView {
        require(hasAccess(userId, bookId)) { "Book access denied" }
        val version = resolveLatestStructuredContentVersion(bookId)
            ?: return BookContentView(
                bookId = bookId,
                contentModel = null,
                contentVersionId = null,
                hasStructuredContent = false,
                chapters = emptyList(),
            )
        val chapters = jdbcClient.sql(
            """
            select chapter_index, anchor, text
            from book_content_blocks
            where content_version_id = :contentVersionId
            and block_index = 0
            order by chapter_index asc
            """.trimIndent(),
        )
            .param("contentVersionId", version.id)
            .query { rs, _ ->
                BookContentChapterSummary(
                    chapterIndex = rs.getInt("chapter_index"),
                    title = rs.getString("text"),
                    anchor = rs.getString("anchor"),
                )
            }
            .list()
        return BookContentView(
            bookId = bookId,
            contentModel = version.contentModel,
            contentVersionId = version.id,
            hasStructuredContent = true,
            chapters = chapters,
        )
    }

    fun getStructuredContentChapter(userId: Long, bookId: Long, chapterIndex: Int): BookContentChapterView {
        require(hasAccess(userId, bookId)) { "Book access denied" }
        val version = resolveLatestStructuredContentVersion(bookId)
            ?: throw IllegalArgumentException("Structured content is not available for this book")
        val chapter = jdbcClient.sql(
            """
            select anchor, text
            from book_content_blocks
            where content_version_id = :contentVersionId
            and chapter_index = :chapterIndex
            and block_index = 0
            limit 1
            """.trimIndent(),
        )
            .param("contentVersionId", version.id)
            .param("chapterIndex", chapterIndex)
            .query { rs, _ ->
                StructuredChapterHeader(
                    anchor = rs.getString("anchor"),
                    title = rs.getString("text"),
                )
            }
            .optional()
            .orElseThrow { IllegalArgumentException("Structured content chapter $chapterIndex was not found") }
        val blocks = jdbcClient.sql(
            """
            select block_index, block_type, anchor, text, plain_text, meta_json
            from book_content_blocks
            where content_version_id = :contentVersionId
            and chapter_index = :chapterIndex
            and block_index > 0
            order by block_index asc
            """.trimIndent(),
        )
            .param("contentVersionId", version.id)
            .param("chapterIndex", chapterIndex)
            .query { rs, _ ->
                BookContentBlockView(
                    blockIndex = rs.getInt("block_index") - 1,
                    type = rs.getString("block_type"),
                    anchor = rs.getString("anchor"),
                    text = rs.getString("text"),
                    plainText = rs.getString("plain_text"),
                    meta = parseMetaJson(rs.getString("meta_json")),
                )
            }
            .list()
        return BookContentChapterView(
            bookId = bookId,
            contentModel = version.contentModel,
            contentVersionId = version.id,
            hasStructuredContent = true,
            chapterIndex = chapterIndex,
            title = chapter.title,
            anchor = chapter.anchor,
            blocks = blocks,
        )
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

    fun getBookResource(userId: Long, bookId: Long, resourceId: String): BookBinaryResource? {
        require(hasAccess(userId, bookId)) { "Book access denied" }
        val fileRef = resolveBookFileRef(bookId)
        val plugin = pluginRegistryService.findPluginById(fileRef.pluginId) ?: return null
        val resource = plugin.extractResource(Path.of(fileRef.storagePath), resourceId) ?: return null
        return BookBinaryResource(
            mimeType = resource.mimeType,
            resource = ByteArrayResource(resource.bytes),
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

    @Transactional
    fun updateAdminBook(bookId: Long, request: UpdateAdminBookRequest): AdminBookDetailView {
        val normalizedGroupName = request.groupName?.trim()?.takeIf { it.isNotEmpty() }
        val updated = jdbcClient.sql(
            """
            update books
            set group_name = :groupName,
                updated_at = :updatedAt
            where id = :bookId
            """.trimIndent(),
        )
            .param("groupName", normalizedGroupName)
            .param("updatedAt", Instant.now().toSqlTimestamp())
            .param("bookId", bookId)
            .update()

        require(updated > 0) { "Book $bookId was not found" }
        return getAdminBookDetail(bookId)
    }

    @Transactional
    fun rebuildStructuredContent(bookId: Long): AdminBookDetailView {
        val fileRef = resolveBookFileRef(bookId)
        val filePath = Path.of(fileRef.storagePath)
        val checksum = sha256(filePath)
        refreshStructuredContent(
            bookId = bookId,
            sourceFileId = fileRef.fileId,
            checksum = checksum,
            pluginId = fileRef.pluginId,
            filePath = filePath,
        )
        return getAdminBookDetail(bookId)
    }

    @Transactional
    fun deleteBooks(bookIds: List<Long>): Int {
        val normalizedIds = bookIds.distinct()
        if (normalizedIds.isEmpty()) {
            return 0
        }

        return jdbcClient.sql(
            """
            delete from books
            where id in (:bookIds)
            """.trimIndent(),
        )
            .param("bookIds", normalizedIds)
            .update()
    }

    fun revokeBookGrant(bookId: Long, userId: Long) {
        jdbcClient.sql(
            """
            delete from user_book_access
            where book_id = :bookId and user_id = :userId
            """.trimIndent(),
        )
            .param("bookId", bookId)
            .param("userId", userId)
            .update()
    }

    fun listBookViewers(bookId: Long): List<BookViewerView> =
        jdbcClient.sql(
            """
            select u.id as user_id,
                   u.username,
                   u.role,
                   u.enabled,
                   case
                       when u.role in ('SUPER_ADMIN', 'LIBRARIAN') then 'GLOBAL_ROLE'
                       else 'EXPLICIT_GRANT'
                   end as access_source,
                   uba.granted_at
            from users u
            left join user_book_access uba on uba.user_id = u.id and uba.book_id = :bookId
            where u.enabled = true
              and (
                  u.role in ('SUPER_ADMIN', 'LIBRARIAN')
                  or uba.book_id is not null
              )
            order by
                case
                    when u.role = 'SUPER_ADMIN' then 0
                    when u.role = 'LIBRARIAN' then 1
                    else 2
                end,
                lower(u.username) asc
            """.trimIndent(),
        )
            .param("bookId", bookId)
            .query { rs, _ ->
                BookViewerView(
                    userId = rs.getLong("user_id"),
                    username = rs.getString("username"),
                    role = rs.getString("role"),
                    enabled = rs.getBoolean("enabled"),
                    accessSource = rs.getString("access_source"),
                    grantedAt = rs.getTimestamp("granted_at")?.toInstant()?.toString(),
                )
            }
            .list()

    fun listGrantableUsers(): List<UserView> =
        jdbcClient.sql(
            """
            select id, username, role, enabled
            from users
            where enabled = true
            order by
                case
                    when role = 'SUPER_ADMIN' then 0
                    when role = 'LIBRARIAN' then 1
                    else 2
                end,
                lower(username) asc
            """.trimIndent(),
        )
            .query { rs, _ ->
                UserView(
                    id = rs.getLong("id"),
                    username = rs.getString("username"),
                    role = rs.getString("role"),
                    enabled = rs.getBoolean("enabled"),
                )
            }
            .list()

    fun listTrackedSourcePaths(sourceId: Long): List<String> =
        jdbcClient.sql(
            """
            select source_path from book_files
            where source_id = :sourceId
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
            select ij.id, ij.book_id, b.title as book_title, ij.source_id, ls.name as source_name,
                   ij.file_id, ij.status, ij.message, ij.created_at, ij.updated_at
            from import_jobs ij
            left join books b on b.id = ij.book_id
            left join library_sources ls on ls.id = ij.source_id
            order by created_at desc
            limit 100
            """.trimIndent(),
        )
            .query { rs, _ ->
                mapOf(
                    "id" to rs.getLong("id"),
                    "bookId" to rs.getObject("book_id"),
                    "bookTitle" to rs.getString("book_title"),
                    "sourceId" to rs.getObject("source_id"),
                    "sourceName" to rs.getString("source_name"),
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
                   bf.manifest_json, bf.capabilities_json,
                   exists(
                       select 1 from book_content_versions bcv
                       where bcv.book_id = b.id and bcv.status = 'READY'
                   ) as has_structured_content,
                   (
                       select bcv.content_model from book_content_versions bcv
                       where bcv.book_id = b.id and bcv.status = 'READY'
                       order by bcv.id desc
                       limit 1
                   ) as content_model,
                   (
                       select bcv.id from book_content_versions bcv
                       where bcv.book_id = b.id and bcv.status = 'READY'
                       order by bcv.id desc
                       limit 1
                   ) as latest_content_version_id
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
            hasStructuredContent = getBoolean("has_structured_content"),
            contentModel = getString("content_model"),
            latestContentVersionId = getObject("latest_content_version_id")?.let { (it as Number).toLong() },
        )
    }

    private fun prepareImport(filePath: Path, plugin: com.privatereader.plugin.BookFormatPlugin): PreparedImport {
        val rawMetadata = plugin.extractMetadata(filePath)
        val metadata = com.privatereader.plugin.BookMetadata(
            title = rawMetadata.title.toPostgresText(),
            author = rawMetadata.author?.toPostgresText(),
            language = rawMetadata.language?.toPostgresText(),
            description = rawMetadata.description?.toPostgresText(),
            tags = rawMetadata.tags.map { it.toPostgresText() },
        )
        val manifestJson = plugin.buildManifest(filePath)?.let { objectMapper.writeValueAsString(it) }
        val capabilitiesJson = objectMapper.writeValueAsString(plugin.capabilities.map { it.name })
        return PreparedImport(
            metadata = metadata,
            format = filePath.fileName.toString().substringAfterLast('.', "bin").lowercase(),
            pluginId = plugin.pluginId,
            capabilitiesJson = capabilitiesJson,
            manifestJson = manifestJson,
            onlineReadable = plugin.capabilities.any { it.name == "READ_ONLINE" },
            indexExcerpt = plugin.extractIndexableContent(filePath)?.text?.toPostgresText()?.take(10_000),
        )
    }

    private fun String.toPostgresText(): String =
        buildString(length) {
            this@toPostgresText.forEach { char ->
                when {
                    char == '\n' || char == '\r' || char == '\t' -> append(char)
                    char.isISOControl() -> append(' ')
                    else -> append(char)
                }
            }
        }.trim()

    private fun refreshExistingFileReference(
        fileId: Long,
        filePath: Path,
        sourceType: String,
        sourceId: Long?,
        format: String,
        sourcePathOverride: String?,
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
            .param("sourcePath", sourcePathOverride ?: filePath.toAbsolutePath().toString())
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

    private fun refreshStructuredContent(
        bookId: Long,
        sourceFileId: Long,
        checksum: String,
        pluginId: String,
        filePath: Path,
    ) {
        val plugin = pluginRegistryService.findPluginById(pluginId) ?: return
        val structuredContent = try {
            plugin.extractStructuredContent(filePath)
        } catch (exception: Exception) {
            insertFailedStructuredContentVersion(bookId, sourceFileId, checksum)
            return
        }

        if (structuredContent == null || structuredContent.chapters.isEmpty()) {
            return
        }

        val now = Instant.now()
        val versionId = jdbcClient.sql(
            """
            insert into book_content_versions (
                book_id, source_file_id, content_model, status, checksum, created_at, updated_at
            ) values (
                :bookId, :sourceFileId, :contentModel, :status, :checksum, :now, :now
            )
            returning id
            """.trimIndent(),
        )
            .param("bookId", bookId)
            .param("sourceFileId", sourceFileId)
            .param("contentModel", structuredContent.contentModel)
            .param("status", CONTENT_STATUS_READY)
            .param("checksum", checksum)
            .param("now", now.toSqlTimestamp())
            .query(Long::class.java)
            .single()

        insertStructuredBlocks(versionId, structuredContent, now)
        markPreviousContentVersionsStale(bookId, versionId, now)
    }

    private fun insertFailedStructuredContentVersion(bookId: Long, sourceFileId: Long, checksum: String) {
        val now = Instant.now()
        jdbcClient.sql(
            """
            insert into book_content_versions (
                book_id, source_file_id, content_model, status, checksum, created_at, updated_at
            ) values (
                :bookId, :sourceFileId, :contentModel, :status, :checksum, :now, :now
            )
            """.trimIndent(),
        )
            .param("bookId", bookId)
            .param("sourceFileId", sourceFileId)
            .param("contentModel", STRUCTURED_CONTENT_MODEL)
            .param("status", CONTENT_STATUS_FAILED)
            .param("checksum", checksum)
            .param("now", now.toSqlTimestamp())
            .update()
    }

    private fun insertStructuredBlocks(versionId: Long, content: StructuredBookContent, now: Instant) {
        content.chapters.forEachIndexed { chapterIndex, chapter ->
            insertStructuredBlock(
                contentVersionId = versionId,
                chapterIndex = chapterIndex,
                blockIndex = 0,
                blockType = StructuredBlockType.HEADING.storageName,
                anchor = chapter.anchor,
                text = chapter.title,
                plainText = chapter.title,
                metaJson = SYNTHETIC_CHAPTER_META_JSON,
                now = now,
            )

            chapter.blocks.forEachIndexed { visibleBlockIndex, block ->
                insertStructuredBlock(
                    contentVersionId = versionId,
                    chapterIndex = chapterIndex,
                    blockIndex = visibleBlockIndex + 1,
                    blockType = block.type.storageName,
                    anchor = block.anchor,
                    text = block.text,
                    plainText = block.plainText,
                    metaJson = block.meta.takeIf { it.isNotEmpty() }?.let(objectMapper::writeValueAsString),
                    now = now,
                )
            }
        }
    }

    private fun insertStructuredBlock(
        contentVersionId: Long,
        chapterIndex: Int,
        blockIndex: Int,
        blockType: String,
        anchor: String,
        text: String,
        plainText: String,
        metaJson: String?,
        now: Instant,
    ) {
        jdbcClient.sql(
            """
            insert into book_content_blocks (
                content_version_id, chapter_index, block_index, block_type, anchor, text, plain_text, meta_json, created_at
            ) values (
                :contentVersionId, :chapterIndex, :blockIndex, :blockType, :anchor, :text, :plainText, :metaJson, :createdAt
            )
            """.trimIndent(),
        )
            .param("contentVersionId", contentVersionId)
            .param("chapterIndex", chapterIndex)
            .param("blockIndex", blockIndex)
            .param("blockType", blockType)
            .param("anchor", anchor)
            .param("text", text)
            .param("plainText", plainText)
            .param("metaJson", metaJson)
            .param("createdAt", now.toSqlTimestamp())
            .update()
    }

    private fun markPreviousContentVersionsStale(bookId: Long, latestVersionId: Long, now: Instant) {
        jdbcClient.sql(
            """
            update book_content_versions
            set status = :staleStatus,
                updated_at = :updatedAt
            where book_id = :bookId
            and status = :readyStatus
            and id <> :latestVersionId
            """.trimIndent(),
        )
            .param("staleStatus", CONTENT_STATUS_STALE)
            .param("updatedAt", now.toSqlTimestamp())
            .param("bookId", bookId)
            .param("readyStatus", CONTENT_STATUS_READY)
            .param("latestVersionId", latestVersionId)
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
            select id, storage_path, plugin_id, format from book_files
            where book_id = :bookId
            order by id desc
            limit 1
            """.trimIndent(),
        )
            .param("bookId", bookId)
            .query { rs, _ ->
                BookFileRef(
                    fileId = rs.getLong("id"),
                    storagePath = rs.getString("storage_path"),
                    pluginId = rs.getString("plugin_id"),
                    format = rs.getString("format"),
                )
            }
            .single()

    private fun resolveLatestStructuredContentVersion(bookId: Long): StructuredContentVersionRef? =
        jdbcClient.sql(
            """
            select id, content_model
            from book_content_versions
            where book_id = :bookId and status = :status
            order by id desc
            limit 1
            """.trimIndent(),
        )
            .param("bookId", bookId)
            .param("status", CONTENT_STATUS_READY)
            .query { rs, _ ->
                StructuredContentVersionRef(
                    id = rs.getLong("id"),
                    contentModel = rs.getString("content_model"),
                )
            }
            .optional()
            .orElse(null)

    private fun parseMetaJson(metaJson: String?): Map<String, Any?> =
        metaJson?.takeIf { it.isNotBlank() }?.let {
            objectMapper.readValue(it, object : TypeReference<Map<String, Any?>>() {})
        } ?: emptyMap()

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

    data class BookBinaryResource(
        val mimeType: String,
        val resource: ByteArrayResource,
    )

    private data class BookFileRef(
        val fileId: Long,
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

    private data class StructuredContentVersionRef(
        val id: Long,
        val contentModel: String,
    )

    private data class StructuredChapterHeader(
        val anchor: String,
        val title: String,
    )

    companion object {
        private const val STRUCTURED_CONTENT_MODEL = "UNIFIED_V1"
        private const val CONTENT_STATUS_READY = "READY"
        private const val CONTENT_STATUS_FAILED = "FAILED"
        private const val CONTENT_STATUS_STALE = "STALE"
        private const val SYNTHETIC_CHAPTER_META_JSON = """{"syntheticChapterTitle":true}"""
    }
}
