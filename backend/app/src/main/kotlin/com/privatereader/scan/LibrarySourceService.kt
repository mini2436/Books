package com.privatereader.scan

import com.privatereader.books.BookService
import com.privatereader.books.CreateLibrarySourceRequest
import com.privatereader.books.LibrarySourceView
import com.privatereader.common.toSqlTimestamp
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Service
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant

@Service
class LibrarySourceService(
    private val jdbcClient: JdbcClient,
    private val bookService: BookService,
) {
    fun createSource(request: CreateLibrarySourceRequest): LibrarySourceView {
        val id = jdbcClient.sql(
            """
            insert into library_sources (name, root_path, enabled, source_type, created_at, updated_at)
            values (:name, :rootPath, :enabled, 'WATCHED_FOLDER', :now, :now)
            returning id
            """.trimIndent(),
        )
            .param("name", request.name)
            .param("rootPath", request.rootPath)
            .param("enabled", request.enabled)
            .param("now", Instant.now().toSqlTimestamp())
            .query(Long::class.java)
            .single()
        return LibrarySourceView(id = id, name = request.name, rootPath = request.rootPath, enabled = request.enabled, lastScanAt = null)
    }

    fun listSources(): List<LibrarySourceView> =
        jdbcClient.sql("select id, name, root_path, enabled, last_scan_at from library_sources order by id asc")
            .query { rs, _ ->
                LibrarySourceView(
                    id = rs.getLong("id"),
                    name = rs.getString("name"),
                    rootPath = rs.getString("root_path"),
                    enabled = rs.getBoolean("enabled"),
                    lastScanAt = rs.getTimestamp("last_scan_at")?.toInstant()?.toString(),
                )
            }
            .list()

    fun scanSource(sourceId: Long): Map<String, Any> {
        val source = jdbcClient.sql("select id, name, root_path, enabled from library_sources where id = :sourceId")
            .param("sourceId", sourceId)
            .query { rs, _ ->
                SourceRecord(
                    id = rs.getLong("id"),
                    name = rs.getString("name"),
                    rootPath = rs.getString("root_path"),
                    enabled = rs.getBoolean("enabled"),
                )
            }
            .single()
        require(source.enabled) { "Source is disabled" }
        val rootPath = Path.of(source.rootPath)
        require(Files.exists(rootPath)) { "Source path does not exist" }

        val seenPaths = mutableSetOf<String>()
        var imported = 0
        // The watcher is intentionally simple and native-friendly: periodic filesystem walking,
        // plugin-based import, and missing-file marking without runtime plugin loading.
        Files.walk(rootPath).use { paths ->
            paths.filter { Files.isRegularFile(it) }
                .forEach { path ->
                    val normalized = path.toAbsolutePath().toString()
                    seenPaths += normalized
                    try {
                        bookService.importDiscoveredFile(path, "WATCHED_FOLDER", source.id, null)
                        imported += 1
                    } catch (_: IllegalArgumentException) {
                    }
                }
        }

        val tracked = bookService.listTrackedSourcePaths(sourceId).toSet()
        (tracked - seenPaths).forEach { missingPath ->
            bookService.markMissingSourcePath(sourceId, missingPath)
        }

        jdbcClient.sql("update library_sources set last_scan_at = :lastScanAt, updated_at = :updatedAt where id = :sourceId")
            .param("lastScanAt", Instant.now().toSqlTimestamp())
            .param("updatedAt", Instant.now().toSqlTimestamp())
            .param("sourceId", sourceId)
            .update()
        return mapOf("sourceId" to source.id, "imported" to imported, "missingMarked" to (tracked - seenPaths).size)
    }

    @Scheduled(fixedDelayString = "\${app.scheduler.scan-delay-ms:1800000}")
    fun scanAllEnabledSources() {
        listSources()
            .filter { it.enabled }
            .forEach { scanSource(it.id) }
    }

    private data class SourceRecord(
        val id: Long,
        val name: String,
        val rootPath: String,
        val enabled: Boolean,
    )
}
