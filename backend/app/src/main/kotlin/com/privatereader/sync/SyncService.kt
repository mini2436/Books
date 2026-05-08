package com.privatereader.sync

import com.privatereader.common.toSqlTimestamp
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
                    // 新增离线创建的批注，并返回服务端 ID 供客户端替换临时 ID。
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
                        .param("updatedAt", Instant.parse(mutation.updatedAt).toSqlTimestamp())
                        .query(Long::class.java)
                        .single()
                    mutation.clientTempId?.let { mappings[it] = annotationId }
                }

                "UPDATE", "DELETE" -> {
                    val existing = getAnnotationRecord(userId, mutation.annotationId ?: -1)
                        ?: throw IllegalArgumentException("Annotation not found")
                    // 批注更新先做版本校验，避免多设备离线修改时静默覆盖。
                    if (existing.version != mutation.baseVersion) {
                        conflicts += SyncConflict(
                            entityType = "annotation",
                            entityId = existing.id,
                            message = "Version conflict detected",
                            serverAnnotation = existing.toView(),
                        )
                    } else {
                        // 更新或软删除指定批注，并递增版本号用于后续冲突检测。
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
                            .param("updatedAt", Instant.parse(mutation.updatedAt).toSqlTimestamp())
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
                // 新增客户端同步上来的书签，可直接带入删除状态以兼容离线操作。
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
                    .param("updatedAt", Instant.parse(mutation.updatedAt).toSqlTimestamp())
                    .update()
            } else {
                // 更新或软删除指定书签，只允许修改当前用户自己的记录。
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
                    .param("updatedAt", Instant.parse(mutation.updatedAt).toSqlTimestamp())
                    .param("bookmarkId", mutation.bookmarkId)
                    .param("userId", userId)
                    .update()
            }
        }

        request.progresses.forEach { mutation ->
            // 查询当前阅读进度的最后更新时间，用于判断是否接受客户端进度。
            val existingUpdatedAt = jdbcClient.sql(
                "select updated_at from reading_progress where user_id = :userId and book_id = :bookId",
            )
                .param("userId", userId)
                .param("bookId", mutation.bookId)
                .query { rs, _ -> rs.getTimestamp("updated_at")?.toInstant() }
                .optional()
                .orElse(null)
            val incomingUpdatedAt = Instant.parse(mutation.updatedAt)
            if (existingUpdatedAt == null || incomingUpdatedAt.isAfter(existingUpdatedAt)) {
                // 写入阅读进度；已有记录时仅用更新的客户端进度覆盖。
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
                    .param("updatedAt", incomingUpdatedAt.toSqlTimestamp())
                    .update()
            }
        }

        return SyncPushResponse(annotationMappings = mappings, conflicts = conflicts)
    }

    fun pull(userId: Long, cursor: Long?): SyncPullResponse {
        val since = cursor?.let { Instant.ofEpochMilli(it) } ?: Instant.EPOCH
        // 拉取指定游标之后发生变更的批注，供客户端增量同步。
        val annotations = jdbcClient.sql(
            """
            select id, book_id, quote_text, note_text, color, anchor_json, version, deleted, updated_at
            from annotations
            where user_id = :userId and updated_at > :since
            order by updated_at asc
            """.trimIndent(),
        )
            .param("userId", userId)
            .param("since", since.toSqlTimestamp())
            .query { rs, _ -> rs.toAnnotationView() }
            .list()

        // 拉取指定游标之后发生变更的书签，供客户端增量同步。
        val bookmarks = jdbcClient.sql(
            """
            select id, book_id, location, label, deleted, updated_at
            from bookmarks
            where user_id = :userId and updated_at > :since
            order by updated_at asc
            """.trimIndent(),
        )
            .param("userId", userId)
            .param("since", since.toSqlTimestamp())
            .query { rs, _ -> rs.toBookmarkView() }
            .list()

        // 拉取指定游标之后发生变更的阅读进度，供客户端增量同步。
        val progresses = jdbcClient.sql(
            """
            select book_id, location, progress_percent, updated_at
            from reading_progress
            where user_id = :userId and updated_at > :since
            order by updated_at asc
            """.trimIndent(),
        )
            .param("userId", userId)
            .param("since", since.toSqlTimestamp())
            .query { rs, _ -> rs.toProgressView() }
            .list()

        // 游标取三类同步数据中的最大更新时间，让客户端下次从该时间之后继续拉取。
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
        // 查询当前用户在指定书籍上的批注列表，按最近更新时间倒序返回。
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
        // 查询当前用户在指定书籍上的书签列表，按最近更新时间倒序返回。
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
        // 查询当前用户的单条批注原始记录，用于同步更新前的版本冲突判断。
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
