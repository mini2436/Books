package com.privatereader.books

import com.fasterxml.jackson.databind.ObjectMapper
import com.privatereader.common.toSqlTimestamp
import com.privatereader.plugin.BookResource
import com.privatereader.pluginruntime.PluginRegistryService
import org.slf4j.LoggerFactory
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Service
import java.nio.file.Path
import java.time.Instant

@Service
class BookResourceStorageService(
    private val jdbcClient: JdbcClient,
    private val pluginRegistryService: PluginRegistryService,
    private val objectMapper: ObjectMapper,
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    fun find(bookId: Long, resourceId: String): BookResource? =
        jdbcClient.sql(
            """
            select mime_type, resource_data
            from book_resources
            where book_id = :bookId and resource_id = :resourceId
            """.trimIndent(),
        )
            .param("bookId", bookId)
            .param("resourceId", resourceId)
            .query { rs, _ ->
                BookResource(
                    mimeType = rs.getString("mime_type"),
                    bytes = rs.getBytes("resource_data"),
                )
            }
            .optional()
            .orElse(null)

    fun store(bookId: Long, resourceId: String, sourceFileHash: String, resource: BookResource) {
        if (resource.bytes.isEmpty()) return
        val now = Instant.now().toSqlTimestamp()
        jdbcClient.sql(
            """
            insert into book_resources (
                book_id, resource_id, mime_type, resource_data, source_file_hash, created_at, updated_at
            ) values (
                :bookId, :resourceId, :mimeType, :resourceData, :sourceFileHash, :now, :now
            )
            on conflict (book_id, resource_id) do update
            set mime_type = excluded.mime_type,
                resource_data = excluded.resource_data,
                source_file_hash = excluded.source_file_hash,
                updated_at = excluded.updated_at
            """.trimIndent(),
        )
            .param("bookId", bookId)
            .param("resourceId", resourceId)
            .param("mimeType", resource.mimeType)
            .param("resourceData", resource.bytes)
            .param("sourceFileHash", sourceFileHash)
            .param("now", now)
            .update()
    }

    fun cacheReferencedResources(
        bookId: Long,
        sourceFileHash: String,
        pluginId: String,
        filePath: Path,
        overwrite: Boolean = false,
    ): BookResourceCacheResult {
        val resourceIds = findReferencedResourceIds(bookId)
        val plugin = pluginRegistryService.findPluginById(pluginId)
            ?: return BookResourceCacheResult(resourceIds.size, 0, 0, 0, resourceIds.size)
        var stored = 0
        var skipped = 0
        var withoutResource = 0
        var failed = 0

        resourceIds.forEach { resourceId ->
            if (!overwrite && hasCurrentResource(bookId, resourceId, sourceFileHash)) {
                skipped += 1
                return@forEach
            }
            try {
                val resource = plugin.extractResource(filePath, resourceId)
                if (resource == null || resource.bytes.isEmpty()) {
                    withoutResource += 1
                    logger.warn("No EPUB resource found for book {} and resource {}", bookId, resourceId)
                } else {
                    store(bookId, resourceId, sourceFileHash, resource)
                    stored += 1
                }
            } catch (exception: Exception) {
                failed += 1
                logger.error("Failed to cache resource {} for book {} from {}", resourceId, bookId, filePath, exception)
            }
        }
        return BookResourceCacheResult(resourceIds.size, stored, skipped, withoutResource, failed)
    }

    private fun findReferencedResourceIds(bookId: Long): List<String> =
        jdbcClient.sql(
            """
            select cb.meta_json
            from book_content_blocks cb
            join book_content_versions cv on cv.id = cb.content_version_id
            where cv.book_id = :bookId
              and cv.status = 'READY'
              and cv.id = (
                  select max(latest_cv.id)
                  from book_content_versions latest_cv
                  where latest_cv.book_id = :bookId and latest_cv.status = 'READY'
              )
              and cb.block_type = 'image'
              and cb.meta_json is not null
            order by cb.chapter_index, cb.block_index
            """.trimIndent(),
        )
            .param("bookId", bookId)
            .query(String::class.java)
            .list()
            .mapNotNull { metaJson ->
                runCatching { objectMapper.readTree(metaJson).path("resourceId").asText() }
                    .getOrNull()
                    ?.takeIf { it.isNotBlank() }
            }
            .distinct()

    private fun hasCurrentResource(bookId: Long, resourceId: String, sourceFileHash: String): Boolean =
        jdbcClient.sql(
            """
            select exists (
                select 1 from book_resources
                where book_id = :bookId
                  and resource_id = :resourceId
                  and source_file_hash = :sourceFileHash
            )
            """.trimIndent(),
        )
            .param("bookId", bookId)
            .param("resourceId", resourceId)
            .param("sourceFileHash", sourceFileHash)
            .query(Boolean::class.java)
            .single()
}

data class BookResourceCacheResult(
    val referenced: Int,
    val stored: Int,
    val skipped: Int,
    val withoutResource: Int,
    val failed: Int,
)
