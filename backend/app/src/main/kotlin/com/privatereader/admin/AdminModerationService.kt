package com.privatereader.admin

import com.privatereader.common.toSqlTimestamp
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Service
import java.sql.ResultSet
import java.time.Instant

@Service
class AdminModerationService(
    private val jdbcClient: JdbcClient,
) {
    fun listAnnotations(): List<AdminAnnotationView> =
        // 查询所有用户批注及其所属用户、书籍信息，供后台审核列表按更新时间展示。
        jdbcClient.sql(
            """
            select a.id,
                   a.user_id,
                   u.username,
                   a.book_id,
                   b.title as book_title,
                   a.quote_text,
                   a.note_text,
                   a.color,
                   a.anchor_json,
                   a.version,
                   a.deleted,
                   a.updated_at
            from annotations a
            join users u on u.id = a.user_id
            join books b on b.id = a.book_id
            order by a.updated_at desc, a.id desc
            """.trimIndent(),
        )
            .query { rs, _ -> rs.toAdminAnnotationView() }
            .list()

    fun updateAnnotationDeleted(annotationId: Long, deleted: Boolean): AdminAnnotationView {
        // 更新指定批注的隐藏状态，并刷新更新时间。
        val updatedRows = jdbcClient.sql(
            """
            update annotations
            set deleted = :deleted,
                updated_at = :updatedAt
            where id = :annotationId
            """.trimIndent(),
        )
            .param("deleted", deleted)
            .param("updatedAt", Instant.now().toSqlTimestamp())
            .param("annotationId", annotationId)
            .update()
        require(updatedRows > 0) { "Annotation not found" }
        return getAnnotation(annotationId) ?: throw IllegalArgumentException("Annotation not found")
    }

    fun listBookmarks(): List<AdminBookmarkView> =
        // 查询所有用户书签及其所属用户、书籍信息，供后台审核列表按更新时间展示。
        jdbcClient.sql(
            """
            select bm.id,
                   bm.user_id,
                   u.username,
                   bm.book_id,
                   b.title as book_title,
                   bm.location,
                   bm.label,
                   bm.deleted,
                   bm.updated_at
            from bookmarks bm
            join users u on u.id = bm.user_id
            join books b on b.id = bm.book_id
            order by bm.updated_at desc, bm.id desc
            """.trimIndent(),
        )
            .query { rs, _ -> rs.toAdminBookmarkView() }
            .list()

    fun updateBookmarkDeleted(bookmarkId: Long, deleted: Boolean): AdminBookmarkView {
        // 更新指定书签的隐藏状态，并刷新更新时间。
        val updatedRows = jdbcClient.sql(
            """
            update bookmarks
            set deleted = :deleted,
                updated_at = :updatedAt
            where id = :bookmarkId
            """.trimIndent(),
        )
            .param("deleted", deleted)
            .param("updatedAt", Instant.now().toSqlTimestamp())
            .param("bookmarkId", bookmarkId)
            .update()
        require(updatedRows > 0) { "Bookmark not found" }
        return getBookmark(bookmarkId) ?: throw IllegalArgumentException("Bookmark not found")
    }

    private fun getAnnotation(annotationId: Long): AdminAnnotationView? =
        // 按批注 ID 查询单条批注详情，用于更新后返回最新状态。
        jdbcClient.sql(
            """
            select a.id,
                   a.user_id,
                   u.username,
                   a.book_id,
                   b.title as book_title,
                   a.quote_text,
                   a.note_text,
                   a.color,
                   a.anchor_json,
                   a.version,
                   a.deleted,
                   a.updated_at
            from annotations a
            join users u on u.id = a.user_id
            join books b on b.id = a.book_id
            where a.id = :annotationId
            """.trimIndent(),
        )
            .param("annotationId", annotationId)
            .query { rs, _ -> rs.toAdminAnnotationView() }
            .optional()
            .orElse(null)

    private fun getBookmark(bookmarkId: Long): AdminBookmarkView? =
        // 按书签 ID 查询单条书签详情，用于更新后返回最新状态。
        jdbcClient.sql(
            """
            select bm.id,
                   bm.user_id,
                   u.username,
                   bm.book_id,
                   b.title as book_title,
                   bm.location,
                   bm.label,
                   bm.deleted,
                   bm.updated_at
            from bookmarks bm
            join users u on u.id = bm.user_id
            join books b on b.id = bm.book_id
            where bm.id = :bookmarkId
            """.trimIndent(),
        )
            .param("bookmarkId", bookmarkId)
            .query { rs, _ -> rs.toAdminBookmarkView() }
            .optional()
            .orElse(null)

    private fun ResultSet.toAdminAnnotationView(): AdminAnnotationView = AdminAnnotationView(
        id = getLong("id"),
        userId = getLong("user_id"),
        username = getString("username"),
        bookId = getLong("book_id"),
        bookTitle = getString("book_title"),
        quoteText = getString("quote_text"),
        noteText = getString("note_text"),
        color = getString("color"),
        anchor = getString("anchor_json"),
        version = getInt("version"),
        deleted = getBoolean("deleted"),
        updatedAt = getTimestamp("updated_at").toInstant().toString(),
    )

    private fun ResultSet.toAdminBookmarkView(): AdminBookmarkView = AdminBookmarkView(
        id = getLong("id"),
        userId = getLong("user_id"),
        username = getString("username"),
        bookId = getLong("book_id"),
        bookTitle = getString("book_title"),
        location = getString("location"),
        label = getString("label"),
        deleted = getBoolean("deleted"),
        updatedAt = getTimestamp("updated_at").toInstant().toString(),
    )
}
