package com.privatereader.sync

import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Service
import java.sql.ResultSet
import java.time.Instant
import kotlin.math.max

@Service
class SyncService(
    private val jdbcClient: JdbcClient,
) {
    fun push(userId: Long, request: SyncPushRequest): SyncPushResponse {
        val mappings = linkedMapOf<String, Long>()
        val conflicts = mutableListOf<SyncConflict>()

        request.annotations.forEach { mutation ->
            when (mutation.action.uppercase()) {
                "CREATE" -> {
                    val annotationId = jdbcClient.sql(
                        """
                        insert into annotations (
                            user_id, book_id, quote_text, note_text, color, anchor_json, version, deleted, created_at, updated_at
                        ) values (
                            :userId, :bookId, :quoteText, :noteText, :color, :anchor, 1, false, :updatedAt, :updatedAt
                        )
                        returning id
                        """.trimIndent(),
                    )
                        .param("userId", userId)
                        .param("bookId", mutation.bookId)
                        .param("quoteText", mutation.quoteText)
                        .param("noteText", mutation.noteText)
                        .param("color", mutation.color)
                        .param("anchor", mutation.anchor)
                        .param("updatedAt", Instant.parse(mutation.updatedAt))
                        .query(Long::class.java)
                        .single()
                    mutation.clientTempId?.let { mappings[it] = annotationId }
                }

                "UPDATE", "DELETE" -> {
                    val existing = getAnnotationRecord(userId, mutation.annotationId ?: -1)
                        ?: throw IllegalArgumentException("Annotation not found")
                    if (existing.version != mutation.baseVersion) {
                        conflicts += SyncConflict(
                            entityType = "annotation",
                            entityId = existing.id,
                            message = "Version conflict detected",
                            serverAnnotation = existing.toView(),
                        )
                    } else {
                        jdbcClient.sql(
                            """
                            update annotations
                            set quote_text = :quoteText,
                                note_text = :noteText,
                                color = :color,
                                anchor_json = :anchor,
                                version = :version,
                                deleted = :deleted,
                                updated_at = :updatedAt
                            where id = :annotationId and user_id = :userId
                            """.trimIndent(),
                        )
                            .param("quoteText", mutation.quoteText)
                            .param("noteText", mutation.noteText)
                            .param("color", mutation.color)
                            .param("anchor", mutation.anchor)
                            .param("version", existing.version + 1)
                            .param("deleted", mutation.action.uppercase() == "DELETE")
                            .param("updatedAt", Instant.parse(mutation.updatedAt))
                            .param("annotationId", existing.id)
                            .param("userId", userId)
                            .update()
                    }
                }
            }
        }

        request.bookmarks.forEach { mutation ->
            val deleted = mutation.action.uppercase() == "DELETE"
            if (mutation.bookmarkId == null) {
                jdbcClient.sql(
                    """
                    insert into bookmarks (user_id, book_id, location, label, deleted, created_at, updated_at)
                    values (:userId, :bookId, :location, :label, :deleted, :updatedAt, :updatedAt)
                    """.trimIndent(),
                )
                    .param("userId", userId)
                    .param("bookId", mutation.bookId)
                    .param("location", mutation.location)
                    .param("label", mutation.label)
                    .param("deleted", deleted)
                    .param("updatedAt", Instant.parse(mutation.updatedAt))
                    .update()
            } else {
                jdbcClient.sql(
                    """
                    update bookmarks
                    set location = :location, label = :label, deleted = :deleted, updated_at = :updatedAt
                    where id = :bookmarkId and user_id = :userId
                    """.trimIndent(),
                )
                    .param("location", mutation.location)
                    .param("label", mutation.label)
                    .param("deleted", deleted)
                    .param("updatedAt", Instant.parse(mutation.updatedAt))
                    .param("bookmarkId", mutation.bookmarkId)
                    .param("userId", userId)
                    .update()
            }
        }

        request.progresses.forEach { mutation ->
            val existingUpdatedAt = jdbcClient.sql(
                "select updated_at from reading_progress where user_id = :userId and book_id = :bookId",
            )
                .param("userId", userId)
                .param("bookId", mutation.bookId)
                .query(Instant::class.java)
                .optional()
                .orElse(null)
            val incomingUpdatedAt = Instant.parse(mutation.updatedAt)
            if (existingUpdatedAt == null || incomingUpdatedAt.isAfter(existingUpdatedAt)) {
                jdbcClient.sql(
                    """
                    insert into reading_progress (user_id, book_id, location, progress_percent, updated_at)
                    values (:userId, :bookId, :location, :progressPercent, :updatedAt)
                    on conflict (user_id, book_id) do update
                    set location = excluded.location,
                        progress_percent = excluded.progress_percent,
                        updated_at = excluded.updated_at
                    """.trimIndent(),
                )
                    .param("userId", userId)
                    .param("bookId", mutation.bookId)
                    .param("location", mutation.location)
                    .param("progressPercent", mutation.progressPercent)
                    .param("updatedAt", incomingUpdatedAt)
                    .update()
            }
        }

        return SyncPushResponse(annotationMappings = mappings, conflicts = conflicts)
    }

    fun pull(userId: Long, cursor: Long?): SyncPullResponse {
        val since = cursor?.let { Instant.ofEpochMilli(it) } ?: Instant.EPOCH
        val annotations = jdbcClient.sql(
            """
            select id, book_id, quote_text, note_text, color, anchor_json, version, deleted, updated_at
            from annotations
            where user_id = :userId and updated_at > :since
            order by updated_at asc
            """.trimIndent(),
        )
            .param("userId", userId)
            .param("since", since)
            .query { rs, _ -> rs.toAnnotationView() }
            .list()

        val bookmarks = jdbcClient.sql(
            """
            select id, book_id, location, label, deleted, updated_at
            from bookmarks
            where user_id = :userId and updated_at > :since
            order by updated_at asc
            """.trimIndent(),
        )
            .param("userId", userId)
            .param("since", since)
            .query { rs, _ -> rs.toBookmarkView() }
            .list()

        val progresses = jdbcClient.sql(
            """
            select book_id, location, progress_percent, updated_at
            from reading_progress
            where user_id = :userId and updated_at > :since
            order by updated_at asc
            """.trimIndent(),
        )
            .param("userId", userId)
            .param("since", since)
            .query { rs, _ -> rs.toProgressView() }
            .list()

        val nextCursor = listOf(
            annotations.maxOfOrNull { Instant.parse(it.updatedAt).toEpochMilli() } ?: 0L,
            bookmarks.maxOfOrNull { Instant.parse(it.updatedAt).toEpochMilli() } ?: 0L,
            progresses.maxOfOrNull { Instant.parse(it.updatedAt).toEpochMilli() } ?: 0L,
            since.toEpochMilli(),
        ).fold(0L, ::max)

        return SyncPullResponse(
            cursor = nextCursor,
            annotations = annotations,
            bookmarks = bookmarks,
            progresses = progresses,
        )
    }

    fun getAnnotations(userId: Long, bookId: Long): List<AnnotationView> =
        jdbcClient.sql(
            """
            select id, book_id, quote_text, note_text, color, anchor_json, version, deleted, updated_at
            from annotations
            where user_id = :userId and book_id = :bookId
            order by updated_at desc
            """.trimIndent(),
        )
            .param("userId", userId)
            .param("bookId", bookId)
            .query { rs, _ -> rs.toAnnotationView() }
            .list()

    fun getBookmarks(userId: Long, bookId: Long): List<BookmarkView> =
        jdbcClient.sql(
            """
            select id, book_id, location, label, deleted, updated_at
            from bookmarks
            where user_id = :userId and book_id = :bookId
            order by updated_at desc
            """.trimIndent(),
        )
            .param("userId", userId)
            .param("bookId", bookId)
            .query { rs, _ -> rs.toBookmarkView() }
            .list()

    fun upsertReadingProgress(userId: Long, mutation: ReadingProgressMutation): ReadingProgressView {
        push(userId, SyncPushRequest(progresses = listOf(mutation)))
        return ReadingProgressView(
            bookId = mutation.bookId,
            location = mutation.location,
            progressPercent = mutation.progressPercent,
            updatedAt = mutation.updatedAt,
        )
    }

    private fun getAnnotationRecord(userId: Long, annotationId: Long): AnnotationRecord? =
        jdbcClient.sql(
            """
            select id, book_id, quote_text, note_text, color, anchor_json, version, deleted, updated_at
            from annotations
            where id = :annotationId and user_id = :userId
            """.trimIndent(),
        )
            .param("annotationId", annotationId)
            .param("userId", userId)
            .query { rs, _ -> rs.toAnnotationRecord() }
            .optional()
            .orElse(null)

    private fun ResultSet.toAnnotationRecord(): AnnotationRecord = AnnotationRecord(
        id = getLong("id"),
        bookId = getLong("book_id"),
        quoteText = getString("quote_text"),
        noteText = getString("note_text"),
        color = getString("color"),
        anchor = getString("anchor_json"),
        version = getInt("version"),
        deleted = getBoolean("deleted"),
        updatedAt = getTimestamp("updated_at").toInstant(),
    )

    private fun AnnotationRecord.toView(): AnnotationView = AnnotationView(
        id = id,
        bookId = bookId,
        quoteText = quoteText,
        noteText = noteText,
        color = color,
        anchor = anchor,
        version = version,
        deleted = deleted,
        updatedAt = updatedAt.toString(),
    )

    private fun ResultSet.toAnnotationView(): AnnotationView = AnnotationView(
        id = getLong("id"),
        bookId = getLong("book_id"),
        quoteText = getString("quote_text"),
        noteText = getString("note_text"),
        color = getString("color"),
        anchor = getString("anchor_json"),
        version = getInt("version"),
        deleted = getBoolean("deleted"),
        updatedAt = getTimestamp("updated_at").toInstant().toString(),
    )

    private fun ResultSet.toBookmarkView(): BookmarkView = BookmarkView(
        id = getLong("id"),
        bookId = getLong("book_id"),
        location = getString("location"),
        label = getString("label"),
        deleted = getBoolean("deleted"),
        updatedAt = getTimestamp("updated_at").toInstant().toString(),
    )

    private fun ResultSet.toProgressView(): ReadingProgressView = ReadingProgressView(
        bookId = getLong("book_id"),
        location = getString("location"),
        progressPercent = getDouble("progress_percent"),
        updatedAt = getTimestamp("updated_at").toInstant().toString(),
    )

    private data class AnnotationRecord(
        val id: Long,
        val bookId: Long,
        val quoteText: String?,
        val noteText: String?,
        val color: String?,
        val anchor: String,
        val version: Int,
        val deleted: Boolean,
        val updatedAt: Instant,
    )
}

