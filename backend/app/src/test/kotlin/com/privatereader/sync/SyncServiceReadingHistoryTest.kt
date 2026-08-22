package com.privatereader.sync

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.jdbc.datasource.DriverManagerDataSource

class SyncServiceReadingHistoryTest {
    @Test
    fun `delete reading history keeps progress annotations and bookmarks`() {
        val dataSource = DriverManagerDataSource(
            "jdbc:h2:mem:${System.nanoTime()};MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
            "sa",
            "",
        )
        val jdbc = JdbcClient.create(dataSource)
        jdbc.sql(
            "create table reading_history (user_id bigint, book_id bigint, last_read_at timestamp with time zone, primary key (user_id, book_id))",
        ).update()
        jdbc.sql(
            "create table reading_progress (user_id bigint, book_id bigint, location text, progress_percent double precision, updated_at timestamp with time zone, primary key (user_id, book_id))",
        ).update()
        jdbc.sql(
            "create table annotations (id bigint primary key, user_id bigint, book_id bigint)",
        ).update()
        jdbc.sql(
            "create table bookmarks (id bigint primary key, user_id bigint, book_id bigint)",
        ).update()
        jdbc.sql(
            "insert into reading_history values (1, 10, current_timestamp), (2, 10, current_timestamp)",
        ).update()
        jdbc.sql(
            "insert into reading_progress values (1, 10, 'chapter-2', 25, current_timestamp)",
        ).update()
        jdbc.sql("insert into annotations values (100, 1, 10)").update()
        jdbc.sql("insert into bookmarks values (200, 1, 10)").update()

        SyncService(jdbc).deleteReadingHistory(userId = 1, bookId = 10)

        assertEquals(0L, count(jdbc, "reading_history", userId = 1))
        assertEquals(1L, count(jdbc, "reading_history", userId = 2))
        assertEquals(1L, count(jdbc, "reading_progress", userId = 1))
        assertEquals(1L, count(jdbc, "annotations", userId = 1))
        assertEquals(1L, count(jdbc, "bookmarks", userId = 1))
    }

    private fun count(jdbc: JdbcClient, table: String, userId: Long): Long =
        jdbc.sql("select count(*) from $table where user_id = :userId and book_id = 10")
            .param("userId", userId)
            .query(Long::class.java)
            .single()
}
