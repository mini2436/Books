package com.privatereader.books

import com.privatereader.common.toSqlTimestamp
import com.privatereader.pluginruntime.PluginRegistryService
import org.slf4j.LoggerFactory
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Service
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant

@Service
class BookCoverBackfillService(
    private val jdbcClient: JdbcClient,
    private val pluginRegistryService: PluginRegistryService,
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    fun backfill(overwrite: Boolean = false): BookCoverBackfillResult {
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
              and (:overwrite = true or b.cover_data is null)
            order by b.id
            """.trimIndent(),
        )
            .param("overwrite", overwrite)
            .query { rs, _ ->
                CoverCandidate(
                    bookId = rs.getLong("book_id"),
                    storagePath = rs.getString("storage_path"),
                    pluginId = rs.getString("plugin_id"),
                    fileHash = rs.getString("file_hash"),
                )
            }
            .list()

        var stored = 0
        var withoutCover = 0
        var failed = 0
        candidates.forEach { candidate ->
            try {
                val path = Path.of(candidate.storagePath)
                require(Files.isRegularFile(path)) { "Source file does not exist: $path" }
                val plugin = requireNotNull(pluginRegistryService.findPluginById(candidate.pluginId)) {
                    "Plugin is not available: ${candidate.pluginId}"
                }
                val cover = plugin.extractCover(path)
                if (cover == null || cover.bytes.isEmpty()) {
                    withoutCover += 1
                    logger.info("No cover found for book {} at {}", candidate.bookId, path)
                } else {
                    jdbcClient.sql(
                        """
                        update books
                        set cover_data = :coverData,
                            cover_content_type = :contentType,
                            cover_source_file_hash = :sourceFileHash,
                            cover_updated_at = :updatedAt
                        where id = :bookId
                        """.trimIndent(),
                    )
                        .param("coverData", cover.bytes)
                        .param("contentType", cover.mimeType)
                        .param("sourceFileHash", candidate.fileHash)
                        .param("updatedAt", Instant.now().toSqlTimestamp())
                        .param("bookId", candidate.bookId)
                        .update()
                    stored += 1
                    logger.info("Stored cover for book {} ({} bytes, {})", candidate.bookId, cover.bytes.size, cover.mimeType)
                }
            } catch (exception: Exception) {
                failed += 1
                logger.error("Failed to backfill cover for book {} from {}", candidate.bookId, candidate.storagePath, exception)
            }
        }

        return BookCoverBackfillResult(
            candidates = candidates.size,
            stored = stored,
            withoutCover = withoutCover,
            failed = failed,
        )
    }

    private data class CoverCandidate(
        val bookId: Long,
        val storagePath: String,
        val pluginId: String,
        val fileHash: String,
    )
}

data class BookCoverBackfillResult(
    val candidates: Int,
    val stored: Int,
    val withoutCover: Int,
    val failed: Int,
)
