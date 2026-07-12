package com.privatereader.books

import org.slf4j.LoggerFactory
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Service
import java.nio.file.Files
import java.nio.file.Path

@Service
class BookResourceBackfillService(
    private val jdbcClient: JdbcClient,
    private val resourceStorageService: BookResourceStorageService,
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    fun backfill(overwrite: Boolean = false): BookResourceBackfillResult {
        val candidates = jdbcClient.sql(
            """
            select b.id as book_id, bf.storage_path, bf.plugin_id, bf.file_hash
            from books b
            join book_files bf on bf.book_id = b.id
            where bf.id = (
                select max(latest_bf.id)
                from book_files latest_bf
                where latest_bf.book_id = b.id
            )
              and exists (
                  select 1
                  from book_content_versions cv
                  join book_content_blocks cb on cb.content_version_id = cv.id
                  where cv.book_id = b.id
                    and cv.status = 'READY'
                    and cb.block_type = 'image'
              )
            order by b.id
            """.trimIndent(),
        )
            .query { rs, _ ->
                ResourceBookCandidate(
                    bookId = rs.getLong("book_id"),
                    storagePath = rs.getString("storage_path"),
                    pluginId = rs.getString("plugin_id"),
                    fileHash = rs.getString("file_hash"),
                )
            }
            .list()

        var referenced = 0
        var stored = 0
        var skipped = 0
        var withoutResource = 0
        var failedResources = 0
        var failedBooks = 0
        candidates.forEach { candidate ->
            try {
                val path = Path.of(candidate.storagePath)
                require(Files.isRegularFile(path)) { "Source file does not exist: $path" }
                val result = resourceStorageService.cacheReferencedResources(
                    bookId = candidate.bookId,
                    sourceFileHash = candidate.fileHash,
                    pluginId = candidate.pluginId,
                    filePath = path,
                    overwrite = overwrite,
                )
                referenced += result.referenced
                stored += result.stored
                skipped += result.skipped
                withoutResource += result.withoutResource
                failedResources += result.failed
            } catch (exception: Exception) {
                failedBooks += 1
                logger.error("Failed to backfill resources for book {} from {}", candidate.bookId, candidate.storagePath, exception)
            }
        }

        return BookResourceBackfillResult(
            books = candidates.size,
            referenced = referenced,
            stored = stored,
            skipped = skipped,
            withoutResource = withoutResource,
            failedResources = failedResources,
            failedBooks = failedBooks,
        )
    }

    private data class ResourceBookCandidate(
        val bookId: Long,
        val storagePath: String,
        val pluginId: String,
        val fileHash: String,
    )
}

data class BookResourceBackfillResult(
    val books: Int,
    val referenced: Int,
    val stored: Int,
    val skipped: Int,
    val withoutResource: Int,
    val failedResources: Int,
    val failedBooks: Int,
)
