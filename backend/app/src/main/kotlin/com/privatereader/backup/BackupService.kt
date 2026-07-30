package com.privatereader.backup

import com.fasterxml.jackson.core.JsonGenerator
import com.fasterxml.jackson.core.type.TypeReference
import com.fasterxml.jackson.databind.ObjectMapper
import com.privatereader.config.AppProperties
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.jdbc.core.PreparedStatementCreator
import org.springframework.jdbc.core.ResultSetExtractor
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.jdbc.BadSqlGrammarException
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import org.springframework.web.multipart.MultipartFile
import java.io.ByteArrayOutputStream
import java.io.FilterOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.sql.ResultSet
import java.sql.Timestamp
import java.security.MessageDigest
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAccessor
import java.util.Base64
import java.util.concurrent.ConcurrentHashMap
import java.util.zip.Deflater
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

private typealias BackupRow = Map<String, Any?>

@Service
class BackupService(
    private val jdbcClient: JdbcClient,
    private val jdbcTemplate: JdbcTemplate,
    private val objectMapper: ObjectMapper,
    private val appProperties: AppProperties,
) {
    private val restoreStatuses = ConcurrentHashMap<String, FullRestoreStatusView>()

    @Transactional(readOnly = true)
    fun export(scope: BackupScope): ByteArray = export(BackupExportRequest(scope = scope))

    @Transactional(readOnly = true)
    fun export(request: BackupExportRequest): ByteArray {
        val output = ByteArrayOutputStream()
        writeExport(request, output)
        return output.toByteArray()
    }

    @Transactional(readOnly = true)
    fun exportToFile(request: BackupExportRequest): Path {
        val temporaryRoot = Path.of(appProperties.storageRoot, "backup-temp")
        Files.createDirectories(temporaryRoot)
        val target = Files.createTempFile(temporaryRoot, "private-reader-", ".zip")
        return try {
            Files.newOutputStream(target).buffered(EXPORT_BUFFER_SIZE).use { writeExport(request, it) }
            target
        } catch (error: Exception) {
            Files.deleteIfExists(target)
            throw error
        }
    }

    /** Removes completed or abandoned prepared downloads after their retry window. */
    @Scheduled(fixedDelayString = "\${app.scheduler.backup-file-cleanup-ms:3600000}")
    fun cleanupTemporaryExports() {
        val temporaryRoot = Path.of(appProperties.storageRoot, "backup-temp")
        if (!Files.isDirectory(temporaryRoot)) return
        val cutoff = Instant.now().minus(TEMPORARY_EXPORT_RETENTION_HOURS, ChronoUnit.HOURS)
        Files.list(temporaryRoot).use { paths ->
            paths.filter { Files.isRegularFile(it) }
                .filter { Files.getLastModifiedTime(it).toInstant().isBefore(cutoff) }
                .forEach { runCatching { Files.deleteIfExists(it) } }
        }
    }

    private fun writeExport(request: BackupExportRequest, output: OutputStream) {
        val manifest = when (request.scope) {
            BackupScope.FULL -> {
                require(request.userIds.isEmpty() && request.bookIds.isEmpty() && request.dataTypes.isEmpty()) {
                    "A full backup does not accept selection filters"
                }
                null
            }
            BackupScope.BOOKS -> bookManifest(request.bookIds)
            BackupScope.USER_DATA -> userDataManifest(request.userIds, request.bookIds, request.dataTypes)
        }
        // ZipOutputStream must be closed to release its Deflater, but a streaming
        // HTTP response stream is owned by the servlet container. Shield the
        // supplied stream from close while still allowing ZIP finalization.
        val nonClosingOutput = object : FilterOutputStream(output) {
            override fun close() = flush()
        }
        ZipOutputStream(nonClosingOutput).use { zip ->
            // JSON compresses well; BEST_SPEED avoids spending excessive CPU on a large manifest.
            zip.setLevel(Deflater.BEST_SPEED)
            zip.putNextEntry(ZipEntry(MANIFEST_ENTRY))
            // Commit HTTP response headers before the potentially long database
            // export so browsers can display their save dialog immediately.
            zip.flush()
            if (request.scope == BackupScope.FULL) {
                writeFullManifest(zip)
            } else {
                zip.write(objectMapper.writeValueAsBytes(requireNotNull(manifest)))
            }
            zip.closeEntry()
            if (request.scope == BackupScope.FULL || request.scope == BackupScope.BOOKS) {
                // EPUB/PDF/CBZ and most MOBI files are already compressed. Recompressing them
                // makes full exports much slower without a meaningful size reduction.
                zip.setLevel(Deflater.NO_COMPRESSION)
                val files = if (request.scope == BackupScope.FULL) {
                    dumpQuery("select storage_path, file_hash from book_files")
                } else {
                    requireNotNull(manifest).tables["book_files"].orEmpty()
                }
                writeManagedBookFiles(zip, files)
            }
        }
    }

    /**
     * Writes the large full-system manifest one database row at a time. PostgreSQL
     * honours fetchSize inside this read-only transaction, so neither the driver nor
     * the application needs to retain an entire table in memory.
     */
    private fun writeFullManifest(output: OutputStream) {
        val generator = objectMapper.factory.createGenerator(output)
            .disable(JsonGenerator.Feature.AUTO_CLOSE_TARGET)
        generator.use {
            it.writeStartObject()
            it.writeStringField("scope", BackupScope.FULL.name)
            it.writeNumberField("formatVersion", FORMAT_VERSION)
            it.writeStringField("createdAt", Instant.now().toString())
            it.writeObjectFieldStart("tables")
            FULL_TABLES.forEach { table ->
                it.writeArrayFieldStart(table)
                streamTable(table) { row -> it.writeObject(row) }
                it.writeEndArray()
            }
            it.writeEndObject()
            it.writeArrayFieldStart("sourceUsers")
            it.writeEndArray()
            it.writeArrayFieldStart("books")
            it.writeEndArray()
            it.writeArrayFieldStart("dataTypes")
            it.writeEndArray()
            it.writeEndObject()
        }
    }

    private fun streamTable(table: String, consume: (BackupRow) -> Unit) {
        require(table in FULL_TABLES) { "Unsupported backup table" }
        jdbcTemplate.query(
            PreparedStatementCreator { connection ->
                connection.prepareStatement(
                    "select * from $table",
                    ResultSet.TYPE_FORWARD_ONLY,
                    ResultSet.CONCUR_READ_ONLY,
                ).apply { fetchSize = EXPORT_FETCH_SIZE }
            },
            ResultSetExtractor<Unit> { resultSet ->
                while (resultSet.next()) consume(resultSet.toRow())
            },
        )
    }

    fun preview(file: MultipartFile): BackupPreviewView {
        val manifest = readArchive(file).manifest
        val previewUsers = if (manifest.scope == BackupScope.FULL) {
            manifest.tables["users"].orEmpty().map { row ->
                BackupUserView(
                    id = (row.getValue("id") as Number).toLong(),
                    username = row["username"]?.toString().orEmpty(),
                    displayName = row["display_name"]?.toString(),
                )
            }
        } else {
            manifest.sourceUsers
        }
        return BackupPreviewView(
            formatVersion = manifest.formatVersion,
            scope = manifest.scope,
            createdAt = manifest.createdAt,
            sourceUsers = previewUsers,
            books = if (manifest.scope == BackupScope.FULL) manifest.tables["books"].orEmpty().size else manifest.books.size,
            annotations = manifest.tables["annotations"].orEmpty().size,
            bookmarks = manifest.tables["bookmarks"].orEmpty().size,
            histories = manifest.tables["reading_history"].orEmpty().size,
            progresses = manifest.tables["reading_progress"].orEmpty().size,
            dataTypes = availableUserDataTypes(manifest),
        )
    }

    @Transactional
    fun restore(
        file: MultipartFile,
        actorId: Long,
        request: BackupRestoreRequest,
        operationId: String? = null,
    ): BackupRestoreResult {
        val trackedOperationId = operationId?.also(::validateOperationId)
        trackedOperationId?.let {
            updateRestoreStatus(it, FullRestorePhase.VALIDATING, 2, message = "正在校验备份文件")
        }
        return try {
            val archive = readArchive(file)
            val restoreScope = request.scope
            require(canRestoreScope(archive.manifest.scope, restoreScope)) {
                "A ${archive.manifest.scope} backup cannot restore $restoreScope data"
            }
            val result = when (restoreScope) {
                BackupScope.FULL -> {
                    require(request.userMappings.isEmpty() && request.dataTypes.isEmpty()) {
                        "A full-system restore does not accept user mappings or data-type filters"
                    }
                    restoreFull(archive, trackedOperationId)
                }
                BackupScope.BOOKS -> {
                    require(request.userMappings.isEmpty() && request.dataTypes.isEmpty()) {
                        "A book restore does not accept user mappings or data-type filters"
                    }
                    restoreBooks(archive, trackedOperationId)
                }
                BackupScope.USER_DATA -> {
                    trackedOperationId?.let {
                        updateRestoreStatus(it, FullRestorePhase.DATABASE, 45, message = "正在恢复用户阅读数据")
                    }
                    restoreUserData(archive.manifest, actorId, request)
                }
            }
            if (restoreScope != BackupScope.FULL) {
                trackedOperationId?.let {
                    updateRestoreStatus(it, FullRestorePhase.COMPLETED, 100, message = "恢复成功")
                }
            }
            result
        } catch (error: Exception) {
            trackedOperationId?.let {
                updateRestoreStatus(it, FullRestorePhase.FAILED, 100, message = "恢复失败，系统数据已回滚")
            }
            throw error
        }
    }

    fun getRestoreStatus(operationId: String): FullRestoreStatusView {
        validateOperationId(operationId)
        return restoreStatuses[operationId] ?: throw IllegalArgumentException("Restore operation not found")
    }

    private fun userDataManifest(
        requestedUserIds: Set<Long>,
        requestedBookIds: Set<Long>,
        requestedTypes: Set<UserDataType>,
    ): BackupManifest {
        require(requestedUserIds.isNotEmpty()) { "Select at least one user for a user-data backup" }
        val userIds = requestedUserIds.sorted()
        val users = jdbcClient.sql(
            "select id, username, display_name from users where id in (:ids) order by id",
        ).param("ids", userIds).query { rs, _ -> BackupUserView(rs.getLong("id"), rs.getString("username"), rs.getString("display_name")) }.list()
        require(users.size == userIds.size) { "One or more selected users were not found" }
        val dataTypes = requestedTypes.ifEmpty { UserDataType.entries.toSet() }
        val tables = dataTypes.associate { type ->
            val table = USER_DATA_TYPE_TABLES.getValue(type)
            table to dumpUserDataTable(table, userIds, requestedBookIds)
        }
        val sourceBookIds = tables.values.flatten().mapNotNull { (it["book_id"] as? Number)?.toLong() }.distinct()
        val books = if (sourceBookIds.isEmpty()) emptyList() else dumpQuery(
            "select b.id as source_book_id, bf.file_hash from books b join book_files bf on bf.book_id = b.id where b.id in (:ids) and bf.id = (select max(x.id) from book_files x where x.book_id = b.id)",
            sourceBookIds,
        )
        return BackupManifest(
            BackupScope.USER_DATA,
            tables = tables,
            sourceUsers = users,
            books = books,
            dataTypes = dataTypes,
        )
    }

    private fun bookManifest(requestedBookIds: Set<Long>): BackupManifest {
        val bookRows = if (requestedBookIds.isEmpty()) {
            dumpTable("books")
        } else {
            dumpQuery("select * from books where id in (:ids) order by id", requestedBookIds.sorted())
        }
        require(requestedBookIds.isEmpty() || bookRows.size == requestedBookIds.size) {
            "One or more selected books were not found"
        }
        val bookIds = bookRows.map { (it.getValue("id") as Number).toLong() }
        val files = dumpByIds("book_files", "book_id", bookIds)
        val formats = dumpByIds("book_formats", "book_id", bookIds)
        val versions = dumpByIds("book_content_versions", "book_id", bookIds)
        val versionIds = versions.map { (it.getValue("id") as Number).toLong() }
        val blocks = dumpByIds("book_content_blocks", "content_version_id", versionIds)
        val resources = dumpByIds("book_resources", "book_id", bookIds)
        val tables = linkedMapOf(
            "books" to bookRows,
            "book_files" to files,
            "book_formats" to formats,
            "book_content_versions" to versions,
            "book_content_blocks" to blocks,
            "book_resources" to resources,
        )
        return BackupManifest(
            scope = BackupScope.BOOKS,
            tables = tables,
            books = bookRows.map { mapOf("source_book_id" to it.getValue("id")) },
        )
    }

    private fun dumpUserDataTable(table: String, userIds: List<Long>, bookIds: Set<Long>): List<BackupRow> {
        var statement = jdbcClient.sql(
            buildString {
                append("select * from $table where user_id in (:userIds)")
                if (bookIds.isNotEmpty()) append(" and book_id in (:bookIds)")
            },
        ).param("userIds", userIds)
        if (bookIds.isNotEmpty()) statement = statement.param("bookIds", bookIds.sorted())
        return statement.query { rs, _ -> rs.toRow() }.list()
    }

    private fun dumpByIds(table: String, column: String, ids: List<Long>): List<BackupRow> =
        if (ids.isEmpty()) emptyList() else dumpQuery("select * from $table where $column in (:ids)", ids)

    private fun restoreBooks(archive: Archive, operationId: String?): BackupRestoreResult {
        requireSupportedFormat(archive.manifest.formatVersion)
        operationId?.let {
            updateRestoreStatus(it, FullRestorePhase.DATABASE, 10, message = "正在匹配书籍与文件")
        }
        val extractedFiles = extractBookFiles(archive, operationId)
        val bookMap = mutableMapOf<Long, Long>()
        val fileMap = mutableMapOf<Long, Long>()
        val versionMap = mutableMapOf<Long, Long>()
        val newSourceBookIds = mutableSetOf<Long>()
        var skippedBooks = 0
        val sourceFilesByBook = archive.manifest.tables["book_files"].orEmpty().groupBy {
            (it.getValue("book_id") as Number).toLong()
        }
        val bookRows = archive.manifest.tables["books"].orEmpty()
        bookRows.forEachIndexed { index, row ->
            val sourceBookId = (row.getValue("id") as Number).toLong()
            val existingBookId = sourceFilesByBook[sourceBookId].orEmpty().firstNotNullOfOrNull { fileRow ->
                val hash = fileRow["file_hash"]?.toString() ?: return@firstNotNullOfOrNull null
                jdbcClient.sql("select book_id from book_files where file_hash = :hash limit 1")
                    .param("hash", hash).query(Long::class.java).optional().orElse(null)
            }
            if (existingBookId != null) {
                bookMap[sourceBookId] = existingBookId
                skippedBooks += 1
            } else {
                bookMap[sourceBookId] = insertReturningId("books", row)
                newSourceBookIds += sourceBookId
            }
            operationId?.let {
                updateRestoreStatus(
                    it,
                    FullRestorePhase.DATABASE,
                    45 + ((index + 1) * 15 / bookRows.size.coerceAtLeast(1)),
                    current = index + 1,
                    total = bookRows.size,
                    message = "正在恢复书籍 ${index + 1}/${bookRows.size}",
                )
            }
        }
        archive.manifest.tables["book_files"].orEmpty().forEach { row ->
            val sourceId = (row.getValue("id") as Number).toLong()
            val sourceBookId = (row.getValue("book_id") as Number).toLong()
            val hash = row["file_hash"]?.toString().orEmpty()
            val existingId = jdbcClient.sql("select id from book_files where file_hash = :hash limit 1")
                .param("hash", hash).query(Long::class.java).optional().orElse(null)
            fileMap[sourceId] = existingId ?: insertReturningId(
                "book_files",
                row + mapOf(
                    "book_id" to bookMap.getValue(sourceBookId),
                    "storage_path" to (extractedFiles[hash] ?: missingBookPath(row, hash)),
                    "source_missing" to (extractedFiles[hash] == null),
                    "source_id" to null,
                ),
            )
        }
        archive.manifest.tables["book_formats"].orEmpty()
            .filter { (it.getValue("book_id") as Number).toLong() in newSourceBookIds }
            .forEach { row ->
                insertReturningId(
                    "book_formats",
                    row + mapOf("book_id" to bookMap.getValue((row.getValue("book_id") as Number).toLong())),
                )
            }
        archive.manifest.tables["book_content_versions"].orEmpty()
            .filter { (it.getValue("book_id") as Number).toLong() in newSourceBookIds }
            .forEach { row ->
                val sourceId = (row.getValue("id") as Number).toLong()
                versionMap[sourceId] = insertReturningId(
                    "book_content_versions",
                    row + mapOf(
                        "book_id" to bookMap.getValue((row.getValue("book_id") as Number).toLong()),
                        "source_file_id" to fileMap.getValue((row.getValue("source_file_id") as Number).toLong()),
                    ),
                )
            }
        archive.manifest.tables["book_content_blocks"].orEmpty().forEach { row ->
            val targetVersionId = versionMap[(row.getValue("content_version_id") as Number).toLong()] ?: return@forEach
            insertReturningId("book_content_blocks", row + mapOf("content_version_id" to targetVersionId))
        }
        archive.manifest.tables["book_resources"].orEmpty()
            .filter { (it.getValue("book_id") as Number).toLong() in newSourceBookIds }
            .forEach { row ->
                insertRow(
                    "book_resources",
                    row + mapOf("book_id" to bookMap.getValue((row.getValue("book_id") as Number).toLong())),
                    excludeId = false,
                )
            }
        resetSequences()
        operationId?.let {
            updateRestoreStatus(it, FullRestorePhase.COMPLETED, 100, message = "书籍恢复成功")
        }
        return BackupRestoreResult(
            scope = BackupScope.BOOKS,
            restoredUsers = 0,
            restoredBooks = bookRows.size,
            annotations = 0,
            bookmarks = 0,
            progresses = 0,
            skippedBooks = skippedBooks,
        )
    }

    private fun restoreFull(archive: Archive, operationId: String?): BackupRestoreResult {
        requireSupportedFormat(archive.manifest.formatVersion)
        operationId?.let {
            updateRestoreStatus(it, FullRestorePhase.DATABASE, 8, message = "正在恢复数据库")
        }
        // Login sessions are deliberately not portable; restoring a database revokes every old session.
        jdbcClient.sql("delete from auth_tokens").update()
        FULL_TABLES.asReversed().forEach { jdbcClient.sql("delete from $it").update() }
        FULL_TABLES.forEachIndexed { index, table ->
            archive.manifest.tables[table].orEmpty().forEach { insert(table, it) }
            operationId?.let {
                val percent = 8 + ((index + 1) * 34 / FULL_TABLES.size)
                updateRestoreStatus(
                    it,
                    FullRestorePhase.DATABASE,
                    percent,
                    current = index + 1,
                    total = FULL_TABLES.size,
                    message = "正在恢复数据库 ${index + 1}/${FULL_TABLES.size}",
                )
            }
        }
        restoreManagedBookFiles(archive, operationId)
        operationId?.let {
            updateRestoreStatus(it, FullRestorePhase.FINALIZING, 97, message = "正在完成数据校验")
        }
        resetSequences()
        val result = BackupRestoreResult(
            scope = BackupScope.FULL,
            restoredUsers = archive.manifest.tables["users"].orEmpty().size,
            restoredBooks = archive.manifest.tables["books"].orEmpty().size,
            annotations = archive.manifest.tables["annotations"].orEmpty().size,
            bookmarks = archive.manifest.tables["bookmarks"].orEmpty().size,
            progresses = archive.manifest.tables["reading_progress"].orEmpty().size,
            histories = archive.manifest.tables["reading_history"].orEmpty().size,
        )
        operationId?.let {
            updateRestoreStatus(it, FullRestorePhase.COMPLETED, 100, message = "系统恢复成功")
        }
        return result
    }

    private fun restoreUserData(manifest: BackupManifest, actorId: Long, request: BackupRestoreRequest): BackupRestoreResult {
        requireSupportedFormat(manifest.formatVersion)
        val availableSourceIds = sourceUsers(manifest).map { it.id }.toSet()
        val sourceIds = request.userMappings.keys
        require(sourceIds.isNotEmpty()) { "Select and map at least one source user" }
        require(availableSourceIds.containsAll(sourceIds)) { "One or more source users are not present in this backup" }
        request.userMappings.values.forEach { targetId ->
            require(userExists(targetId)) { "Target user $targetId was not found" }
        }
        val availableTypes = availableUserDataTypes(manifest)
        val dataTypes = request.dataTypes.ifEmpty { availableTypes }
        require(dataTypes.isNotEmpty()) { "Select at least one user data type" }
        require(availableTypes.containsAll(dataTypes)) { "One or more selected data types are not present in this backup" }
        val tables = dataTypes.associate { type ->
            val table = USER_DATA_TYPE_TABLES.getValue(type)
            table to manifest.tables[table].orEmpty().filter { row ->
                (row["user_id"] as? Number)?.toLong() in sourceIds
            }
        }
        val sourceBookIds = tables.values.flatten()
            .mapNotNull { (it["book_id"] as? Number)?.toLong() }
            .toSet()
        val scopedManifest = manifest.copy(
            tables = tables,
            sourceUsers = sourceUsers(manifest).filter { it.id in sourceIds },
            books = bookReferences(manifest, sourceBookIds),
            dataTypes = dataTypes,
        )
        val bookMap = resolveBooks(scopedManifest.books)
        var skippedBooks = 0
        if (request.mode == UserDataRestoreMode.REPLACE) {
            deleteRestoreScope(scopedManifest, request.userMappings, bookMap)
        }
        restoreRows(scopedManifest.tables["user_book_access"].orEmpty(), request.userMappings, bookMap) { row, userId, bookId ->
            if (bookId == null) { skippedBooks++; return@restoreRows }
            if (!userBookRowExists("user_book_access", userId, bookId)) {
                jdbcClient.sql("insert into user_book_access (user_id, book_id, granted_by, granted_at) values (:userId, :bookId, :actorId, :grantedAt)")
                    .param("userId", userId).param("bookId", bookId).param("actorId", actorId).param("grantedAt", timestamp(row["granted_at"])) .update()
            }
        }
        restoreRows(scopedManifest.tables["user_book_groups"].orEmpty(), request.userMappings, bookMap) { row, userId, bookId ->
            if (bookId == null) { skippedBooks++; return@restoreRows }
            deleteUserBookRow("user_book_groups", userId, bookId)
            jdbcClient.sql("insert into user_book_groups (user_id, book_id, group_name, updated_at) values (:userId, :bookId, :groupName, :updatedAt)")
                .param("userId", userId).param("bookId", bookId).param("groupName", row["group_name"]).param("updatedAt", timestamp(row["updated_at"])) .update()
        }
        restoreRows(scopedManifest.tables["annotations"].orEmpty(), request.userMappings, bookMap) { row, userId, bookId ->
            if (bookId == null) { skippedBooks++; return@restoreRows }
            val existingId = jdbcClient.sql("select id from annotations where user_id=:userId and book_id=:bookId and anchor_json=:anchor and created_at=:created limit 1")
                .param("userId", userId).param("bookId", bookId).param("anchor", row["anchor_json"]).param("created", timestamp(row["created_at"]))
                .query(Long::class.java).optional().orElse(null)
            if (existingId == null) {
                jdbcClient.sql("insert into annotations (user_id, book_id, quote_text, note_text, color, anchor_json, version, deleted, created_at, updated_at) values (:userId,:bookId,:quote,:note,:color,:anchor,:version,:deleted,:created,:updated)")
                    .param("userId", userId).param("bookId", bookId).param("quote", row["quote_text"]).param("note", row["note_text"]).param("color", row["color"]).param("anchor", row["anchor_json"])
                    .param("version", (row["version"] as Number).toInt()).param("deleted", row["deleted"] as Boolean).param("created", timestamp(row["created_at"])).param("updated", timestamp(row["updated_at"])) .update()
            } else {
                jdbcClient.sql("update annotations set quote_text=:quote,note_text=:note,color=:color,anchor_json=:anchor,version=:version,deleted=:deleted,updated_at=:updated where id=:id")
                    .param("quote", row["quote_text"]).param("note", row["note_text"]).param("color", row["color"]).param("anchor", row["anchor_json"])
                    .param("version", (row["version"] as Number).toInt()).param("deleted", row["deleted"] as Boolean).param("updated", timestamp(row["updated_at"])).param("id", existingId).update()
            }
        }
        restoreRows(scopedManifest.tables["bookmarks"].orEmpty(), request.userMappings, bookMap) { row, userId, bookId ->
            if (bookId == null) { skippedBooks++; return@restoreRows }
            val existingId = jdbcClient.sql("select id from bookmarks where user_id=:userId and book_id=:bookId and location=:location and created_at=:created limit 1")
                .param("userId", userId).param("bookId", bookId).param("location", row["location"]).param("created", timestamp(row["created_at"]))
                .query(Long::class.java).optional().orElse(null)
            if (existingId == null) {
                jdbcClient.sql("insert into bookmarks (user_id, book_id, location, label, deleted, created_at, updated_at) values (:userId,:bookId,:location,:label,:deleted,:created,:updated)")
                    .param("userId", userId).param("bookId", bookId).param("location", row["location"]).param("label", row["label"]).param("deleted", row["deleted"] as Boolean).param("created", timestamp(row["created_at"])).param("updated", timestamp(row["updated_at"])) .update()
            } else {
                jdbcClient.sql("update bookmarks set label=:label,deleted=:deleted,updated_at=:updated where id=:id")
                    .param("label", row["label"]).param("deleted", row["deleted"] as Boolean).param("updated", timestamp(row["updated_at"])).param("id", existingId).update()
            }
        }
        restoreRows(scopedManifest.tables["reading_history"].orEmpty(), request.userMappings, bookMap) { row, userId, bookId ->
            if (bookId == null) { skippedBooks++; return@restoreRows }
            val existing = rowTimestamp("reading_history", "last_read_at", userId, bookId)
            val incoming = timestamp(row["last_read_at"])
            if (request.mode == UserDataRestoreMode.REPLACE || existing == null || incoming.after(existing)) {
                deleteUserBookRow("reading_history", userId, bookId)
                jdbcClient.sql("insert into reading_history (user_id, book_id, last_read_at) values (:userId,:bookId,:lastReadAt)")
                    .param("userId", userId).param("bookId", bookId).param("lastReadAt", incoming).update()
            }
        }
        restoreRows(scopedManifest.tables["reading_progress"].orEmpty(), request.userMappings, bookMap) { row, userId, bookId ->
            if (bookId == null) { skippedBooks++; return@restoreRows }
            val existing = rowTimestamp("reading_progress", "updated_at", userId, bookId)
            val incoming = timestamp(row["updated_at"])
            if (request.mode == UserDataRestoreMode.REPLACE || existing == null || incoming.after(existing)) {
                deleteUserBookRow("reading_progress", userId, bookId)
                jdbcClient.sql("insert into reading_progress (user_id, book_id, location, progress_percent, updated_at) values (:userId,:bookId,:location,:percent,:updated)")
                    .param("userId", userId).param("bookId", bookId).param("location", row["location"]).param("percent", (row["progress_percent"] as Number).toDouble()).param("updated", incoming).update()
            }
        }
        return BackupRestoreResult(
            scope = BackupScope.USER_DATA,
            restoredUsers = sourceIds.size,
            restoredBooks = bookMap.size,
            annotations = scopedManifest.tables["annotations"].orEmpty().size,
            bookmarks = scopedManifest.tables["bookmarks"].orEmpty().size,
            progresses = scopedManifest.tables["reading_progress"].orEmpty().size,
            histories = scopedManifest.tables["reading_history"].orEmpty().size,
            skippedBooks = skippedBooks,
        )
    }

    private fun restoreRows(rows: List<BackupRow>, mappings: Map<Long, Long>, books: Map<Long, Long>, action: (BackupRow, Long, Long?) -> Unit) = rows.forEach { row ->
        val sourceUserId = (row["user_id"] as Number).toLong()
        val sourceBookId = (row["book_id"] as Number).toLong()
        action(row, mappings.getValue(sourceUserId), books[sourceBookId])
    }

    private fun deleteRestoreScope(manifest: BackupManifest, mappings: Map<Long, Long>, books: Map<Long, Long>) {
        manifest.tables.forEach { (table, rows) ->
            if (table !in USER_DATA_TABLES) return@forEach
            rows.groupBy { mappings.getValue((it.getValue("user_id") as Number).toLong()) }.forEach { (targetUserId, userRows) ->
                val targetBookIds = userRows.mapNotNull { books[(it.getValue("book_id") as Number).toLong()] }.distinct()
                if (targetBookIds.isNotEmpty()) {
                    jdbcClient.sql("delete from $table where user_id = :userId and book_id in (:bookIds)")
                        .param("userId", targetUserId).param("bookIds", targetBookIds).update()
                }
            }
        }
    }

    private fun rowTimestamp(table: String, column: String, userId: Long, bookId: Long): Timestamp? =
        jdbcClient.sql("select $column from $table where user_id=:userId and book_id=:bookId")
            .param("userId", userId).param("bookId", bookId).query(Timestamp::class.java).optional().orElse(null)

    private fun userBookRowExists(table: String, userId: Long, bookId: Long): Boolean = jdbcClient.sql(
        "select exists(select 1 from $table where user_id = :userId and book_id = :bookId)",
    ).param("userId", userId).param("bookId", bookId).query(Boolean::class.java).single()

    private fun deleteUserBookRow(table: String, userId: Long, bookId: Long) {
        jdbcClient.sql("delete from $table where user_id = :userId and book_id = :bookId")
            .param("userId", userId).param("bookId", bookId).update()
    }

    private fun resolveBooks(books: List<BackupRow>): Map<Long, Long> = books.mapNotNull { row ->
        val sourceId = (row["source_book_id"] as Number).toLong()
        val targetId = jdbcClient.sql("select book_id from book_files where file_hash = :hash limit 1").param("hash", row["file_hash"]).query(Long::class.java).optional().orElse(null)
        targetId?.let { sourceId to it }
    }.toMap()

    private fun sourceUsers(manifest: BackupManifest): List<BackupUserView> =
        if (manifest.sourceUsers.isNotEmpty()) manifest.sourceUsers else manifest.tables["users"].orEmpty().map { row ->
            BackupUserView(
                id = (row.getValue("id") as Number).toLong(),
                username = row["username"]?.toString().orEmpty(),
                displayName = row["display_name"]?.toString(),
            )
        }

    private fun availableUserDataTypes(manifest: BackupManifest): Set<UserDataType> =
        manifest.dataTypes.ifEmpty {
            USER_DATA_TYPE_TABLES.filterValues { table -> table in manifest.tables }.keys
        }

    private fun bookReferences(manifest: BackupManifest, sourceBookIds: Set<Long>): List<BackupRow> {
        if (sourceBookIds.isEmpty()) return emptyList()
        if (manifest.books.isNotEmpty()) {
            return manifest.books.filter { (it["source_book_id"] as? Number)?.toLong() in sourceBookIds }
        }
        return manifest.tables["book_files"].orEmpty()
            .filter { (it["book_id"] as? Number)?.toLong() in sourceBookIds }
            .mapNotNull { row ->
                val sourceBookId = (row["book_id"] as? Number)?.toLong() ?: return@mapNotNull null
                val hash = row["file_hash"]?.toString()?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                mapOf("source_book_id" to sourceBookId, "file_hash" to hash)
            }
            .distinctBy { it["source_book_id"] }
    }

    private fun canRestoreScope(archiveScope: BackupScope, restoreScope: BackupScope): Boolean = when (archiveScope) {
        BackupScope.FULL -> true
        BackupScope.BOOKS -> restoreScope == BackupScope.BOOKS
        BackupScope.USER_DATA -> restoreScope == BackupScope.USER_DATA
    }

    private fun writeManagedBookFiles(zip: ZipOutputStream, files: List<BackupRow>) {
        files.forEach { row ->
            val path = row["storage_path"] as? String ?: return@forEach
            val hash = row["file_hash"] as? String ?: return@forEach
            val file = Path.of(path)
            if (Files.isRegularFile(file)) {
                zip.putNextEntry(ZipEntry("books/$hash"))
                Files.newInputStream(file).buffered(EXPORT_BUFFER_SIZE).use { input ->
                    input.copyTo(zip, EXPORT_BUFFER_SIZE)
                }
                zip.closeEntry()
            }
        }
    }

    private fun extractBookFiles(archive: Archive, operationId: String?): Map<String, String> {
        val restoredRoot = Path.of(appProperties.storageRoot, "restored-backup")
        val extracted = mutableMapOf<String, String>()
        val entries = archive.manifest.tables["book_files"].orEmpty()
        val total = entries.size
        var current = 0
        ZipInputStream(archive.openStream()).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                if (entry.name.startsWith("books/") && !entry.isDirectory) {
                    val hash = entry.name.removePrefix("books/")
                    require(hash.matches(Regex("[a-fA-F0-9]{32,128}"))) { "Invalid backup book entry" }
                    val row = entries.firstOrNull { it["file_hash"]?.toString() == hash }
                        ?: throw IllegalArgumentException("Unexpected book file in backup")
                    val format = row["format"]?.toString()?.ifBlank { "book" } ?: "book"
                    Files.createDirectories(restoredRoot)
                    val target = restoredRoot.resolve("$hash.$format")
                    val temporary = restoredRoot.resolve("$hash.$format.part")
                    val digest = MessageDigest.getInstance("SHA-256")
                    var written = 0L
                    try {
                        Files.newOutputStream(temporary).use { output ->
                            val buffer = ByteArray(DEFAULT_BUFFER_SIZE * 8)
                            while (true) {
                                val read = zip.read(buffer)
                                if (read <= 0) break
                                output.write(buffer, 0, read)
                                digest.update(buffer, 0, read)
                                written += read
                            }
                        }
                        verifyBookEntry(row, hash, written, digest.digest())
                        try {
                            Files.move(temporary, target, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
                        } catch (_: Exception) {
                            Files.move(temporary, target, StandardCopyOption.REPLACE_EXISTING)
                        }
                    } finally {
                        Files.deleteIfExists(temporary)
                    }
                    extracted[hash] = target.toAbsolutePath().toString()
                    current += 1
                    operationId?.let {
                        updateRestoreStatus(
                            it,
                            FullRestorePhase.FILES,
                            10 + (current * 35 / total.coerceAtLeast(1)),
                            current = current,
                            total = total,
                            message = "正在解包书籍文件 $current/$total",
                        )
                    }
                }
                zip.closeEntry()
            }
        }
        return extracted
    }

    private fun missingBookPath(row: BackupRow, hash: String): String {
        val format = row["format"]?.toString()?.ifBlank { "book" } ?: "book"
        return Path.of(appProperties.storageRoot, "restored-backup", "$hash.$format").toAbsolutePath().toString()
    }

    private fun restoreManagedBookFiles(archive: Archive, operationId: String?) {
        val restoredRoot = Path.of(appProperties.storageRoot, "restored-backup")
        val fileSizes = archive.manifest.tables["book_files"].orEmpty().mapNotNull { row ->
            val hash = row["file_hash"] as? String ?: return@mapNotNull null
            hash to ((row["file_size"] as? Number)?.toLong() ?: 0L)
        }.toMap()
        val totalFiles = fileSizes.size
        val totalBytes = fileSizes.values.sum().coerceAtLeast(1L)
        var restoredFiles = 0
        var restoredBytes = 0L
        var lastReportedBytes = 0L
        operationId?.let {
            updateRestoreStatus(it, FullRestorePhase.FILES, 42, total = totalFiles, message = "正在准备恢复书籍文件")
        }
        ZipInputStream(archive.openStream()).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                if (entry.name.startsWith("books/") && !entry.isDirectory) {
                    val hash = entry.name.removePrefix("books/")
                    require(hash.matches(Regex("[a-fA-F0-9]{32,128}"))) { "Invalid backup book entry" }
                    val format = jdbcClient.sql("select format from book_files where file_hash = :hash limit 1").param("hash", hash).query(String::class.java).optional().orElse("book")
                    Files.createDirectories(restoredRoot)
                    val target = restoredRoot.resolve("$hash.$format")
                    val temporary = restoredRoot.resolve("$hash.$format.part")
                    val digest = MessageDigest.getInstance("SHA-256")
                    var entryBytes = 0L
                    try {
                        Files.newOutputStream(temporary).use { output ->
                            val buffer = ByteArray(DEFAULT_BUFFER_SIZE * 8)
                            while (true) {
                                val read = zip.read(buffer)
                                if (read <= 0) break
                                output.write(buffer, 0, read)
                                digest.update(buffer, 0, read)
                                entryBytes += read
                                restoredBytes += read
                                if (restoredBytes - lastReportedBytes >= PROGRESS_REPORT_BYTES) {
                                    lastReportedBytes = restoredBytes
                                    operationId?.let {
                                        updateRestoreStatus(
                                            it,
                                            FullRestorePhase.FILES,
                                            42 + (restoredBytes * 53 / totalBytes).toInt().coerceIn(0, 53),
                                            current = restoredFiles + 1,
                                            total = totalFiles,
                                            message = "正在恢复书籍文件 ${restoredFiles + 1}/$totalFiles",
                                        )
                                    }
                                }
                            }
                        }
                        val sourceRow = archive.manifest.tables["book_files"].orEmpty()
                            .first { it["file_hash"]?.toString() == hash }
                        verifyBookEntry(sourceRow, hash, entryBytes, digest.digest())
                        try {
                            Files.move(temporary, target, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
                        } catch (_: Exception) {
                            Files.move(temporary, target, StandardCopyOption.REPLACE_EXISTING)
                        }
                    } finally {
                        Files.deleteIfExists(temporary)
                    }
                    restoredFiles += 1
                    jdbcClient.sql("update book_files set storage_path = :path, source_missing = false where file_hash = :hash").param("path", target.toAbsolutePath().toString()).param("hash", hash).update()
                    operationId?.let {
                        updateRestoreStatus(
                            it,
                            FullRestorePhase.FILES,
                            42 + (restoredBytes * 53 / totalBytes).toInt().coerceIn(0, 53),
                            current = restoredFiles,
                            total = totalFiles,
                            message = "已恢复书籍文件 $restoredFiles/$totalFiles",
                        )
                    }
                }
                zip.closeEntry()
            }
        }
    }

    private fun validateOperationId(operationId: String) {
        require(operationId.matches(Regex("[A-Za-z0-9-]{8,64}"))) { "Invalid restore operation id" }
    }

    private fun verifyBookEntry(row: BackupRow, expectedHash: String, actualSize: Long, digest: ByteArray) {
        val expectedSize = (row["file_size"] as? Number)?.toLong()
        if (expectedSize != null) require(actualSize == expectedSize) { "Backup book file size mismatch" }
        val actualHash = digest.joinToString("") { "%02x".format(it) }
        require(actualHash.equals(expectedHash, ignoreCase = true)) { "Backup book file hash mismatch" }
    }

    private fun updateRestoreStatus(
        operationId: String,
        phase: FullRestorePhase,
        percent: Int,
        current: Int = 0,
        total: Int = 0,
        message: String,
    ) {
        restoreStatuses[operationId] = FullRestoreStatusView(
            operationId = operationId,
            phase = phase,
            percent = percent.coerceIn(0, 100),
            current = current,
            total = total,
            message = message,
            updatedAt = Instant.now().toString(),
        )
        if (restoreStatuses.size > MAX_RESTORE_STATUSES) {
            restoreStatuses.entries.sortedBy { it.value.updatedAt }.take(restoreStatuses.size - MAX_RESTORE_STATUSES)
                .forEach { restoreStatuses.remove(it.key) }
        }
    }

    private fun readArchive(file: MultipartFile): Archive {
        val manifestBytes = ZipInputStream(file.inputStream).use { zip ->
            var found: ByteArray? = null
            while (true) {
                val entry = zip.nextEntry ?: break
                if (entry.name == MANIFEST_ENTRY) { found = zip.readBytes(); break }
            }
            found
        } ?: throw IllegalArgumentException("Backup manifest is missing")
        val manifest = objectMapper.readValue(manifestBytes, object : TypeReference<BackupManifest>() {})
        requireSupportedFormat(manifest.formatVersion)
        return Archive(manifest) { file.inputStream }
    }

    private fun requireSupportedFormat(formatVersion: Int) {
        require(formatVersion == FORMAT_VERSION) { "Unsupported backup format $formatVersion" }
    }

    private fun dumpTable(table: String): List<BackupRow> = dumpQuery("select * from $table")

    private fun dumpQuery(sql: String, ids: List<Long>? = null): List<BackupRow> {
        var statement = jdbcClient.sql(sql)
        if (ids != null) statement = statement.param("ids", ids)
        return statement.query { rs, _ -> rs.toRow() }.list()
    }

    private fun ResultSet.toRow(): BackupRow {
        val metadata = metaData
        return buildMap {
            for (index in 1..metadata.columnCount) {
                val key = metadata.getColumnLabel(index).lowercase()
                val value = getObject(index)
                put(key, when (value) {
                    is Timestamp -> value.toInstant().toString()
                    is TemporalAccessor -> value.toString()
                    else -> value
                })
            }
        }
    }

    private fun insert(table: String, row: BackupRow) {
        insertRow(table, row, excludeId = false)
    }

    private fun insertReturningId(table: String, row: BackupRow): Long {
        val columns = row.keys.filterNot { it == "id" }
        val sql = "insert into $table (${columns.joinToString()}) values (${columns.joinToString { ":$it" }}) returning id"
        var statement = jdbcClient.sql(sql)
        columns.forEach { column -> statement = statement.param(column, databaseValue(table, column, row[column])) }
        return try {
            statement.query(Long::class.java).single()
        } catch (_: BadSqlGrammarException) {
            // H2 (used by the test suite) does not implement PostgreSQL's RETURNING clause.
            insertRow(table, row, excludeId = true)
            jdbcClient.sql("select max(id) from $table").query(Long::class.java).single()
        }
    }

    private fun insertRow(table: String, row: BackupRow, excludeId: Boolean) {
        val columns = row.keys.filterNot { excludeId && it == "id" }
        val sql = "insert into $table (${columns.joinToString()}) values (${columns.joinToString { ":$it" }})"
        var statement = jdbcClient.sql(sql)
        columns.forEach { column -> statement = statement.param(column, databaseValue(table, column, row[column])) }
        statement.update()
    }

    private fun databaseValue(table: String, column: String, value: Any?): Any? = when {
        value == null -> null
        "$table.$column" in BINARY_COLUMNS -> Base64.getDecoder().decode(value as String)
        column.endsWith("_at") || column == "expires_at" || column == "refresh_expires_at" -> timestamp(value)
        else -> value
    }

    private fun timestamp(value: Any?): Timestamp = when (value) {
        is Timestamp -> value
        is Instant -> Timestamp.from(value)
        else -> Timestamp.from(Instant.parse(value.toString()))
    }

    private fun userExists(id: Long): Boolean = jdbcClient.sql("select exists(select 1 from users where id = :id)").param("id", id).query(Boolean::class.java).single()

    private fun resetSequences() {
        // PostgreSQL sequences are not advanced when explicit IDs are restored. H2 tests do not implement setval.
        ID_TABLES.forEach { table ->
            runCatching {
                jdbcClient.sql(
                    "select setval(pg_get_serial_sequence('$table', 'id'), coalesce((select max(id) from $table), 1), exists(select 1 from $table))",
                ).query(Long::class.java).single()
            }
        }
    }

    private data class Archive(
        val manifest: BackupManifest,
        val openStream: () -> InputStream,
    )
    private data class BackupManifest(
        val scope: BackupScope,
        val formatVersion: Int = FORMAT_VERSION,
        val createdAt: String = Instant.now().toString(),
        val tables: Map<String, List<BackupRow>> = emptyMap(),
        val sourceUsers: List<BackupUserView> = emptyList(),
        val books: List<BackupRow> = emptyList(),
        val dataTypes: Set<UserDataType> = emptySet(),
    )

    companion object {
        private const val FORMAT_VERSION = 2
        private const val MANIFEST_ENTRY = "manifest.json"
        private const val PROGRESS_REPORT_BYTES = 4L * 1024 * 1024
        private const val EXPORT_BUFFER_SIZE = 256 * 1024
        private const val EXPORT_FETCH_SIZE = 500
        private const val TEMPORARY_EXPORT_RETENTION_HOURS = 24L
        private const val MAX_RESTORE_STATUSES = 100
        private val FULL_TABLES = listOf("users", "books", "library_sources", "book_files", "book_formats", "book_content_versions", "book_content_blocks", "book_resources", "user_book_access", "user_book_groups", "annotations", "bookmarks", "reading_progress", "reading_history", "library_source_files", "import_jobs", "plugin_registry", "plugin_error_logs")
        private val USER_DATA_TYPE_TABLES = mapOf(
            UserDataType.BOOK_ACCESS to "user_book_access",
            UserDataType.BOOK_GROUPS to "user_book_groups",
            UserDataType.ANNOTATIONS to "annotations",
            UserDataType.BOOKMARKS to "bookmarks",
            UserDataType.READING_HISTORY to "reading_history",
            UserDataType.READING_PROGRESS to "reading_progress",
        )
        private val USER_DATA_TABLES = USER_DATA_TYPE_TABLES.values.toList()
        private val ID_TABLES = listOf("users", "books", "library_sources", "book_files", "book_formats", "book_content_versions", "book_content_blocks", "annotations", "bookmarks", "import_jobs", "plugin_error_logs")
        private val BINARY_COLUMNS = setOf("users.avatar_data", "books.cover_data", "book_resources.resource_data")
    }
}
