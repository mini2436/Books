package com.privatereader.scan

import com.privatereader.books.BookService
import com.privatereader.books.ClientLibraryFileSummaryRequest
import com.privatereader.books.ClientLibraryScanPlanRequest
import com.privatereader.config.AppProperties
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import org.mockito.kotlin.mock
import org.mockito.kotlin.verify
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.jdbc.datasource.DriverManagerDataSource

class LibrarySourceServiceTest {
    @Test
    fun `client scan plans only changed files and marks missing paths`() {
        val fixture = fixture()
        fixture.jdbc.sql(
            """
            insert into library_sources (
                id, name, root_path, enabled, source_type, scan_interval_minutes, created_at, updated_at
            ) values (1, '客户端目录', 'Books', false, 'CLIENT_FOLDER', 60, current_timestamp, current_timestamp);
            insert into library_source_files (
                source_id, relative_path, file_size, last_modified_millis, client_signature, updated_at
            ) values
                (1, 'unchanged.epub', 100, 200, '100:200', current_timestamp),
                (1, 'removed.pdf', 300, 400, '300:400', current_timestamp)
            """.trimIndent(),
        ).update()

        val plan = fixture.service.planClientScan(
            1,
            ClientLibraryScanPlanRequest(
                files = listOf(
                    ClientLibraryFileSummaryRequest("unchanged.epub", 100, 200),
                    ClientLibraryFileSummaryRequest("new/book.pdf", 500, 600),
                ),
            ),
        )

        assertEquals(listOf("new/book.pdf"), plan.uploadPaths)
        assertEquals(1, plan.unchanged)
        assertEquals(1, plan.missingMarked)
        verify(fixture.bookService).markMissingSourcePath(1, "removed.pdf")
        assertEquals(
            0,
            fixture.jdbc.sql(
                "select count(*) from library_source_files where source_id = 1 and relative_path = 'removed.pdf'",
            ).query(Int::class.java).single(),
        )
    }

    @Test
    fun `deleting a source keeps imported books and detaches their files`() {
        val fixture = fixture()
        fixture.jdbc.sql(
            """
            insert into library_sources (
                id, name, root_path, enabled, source_type, scan_interval_minutes, created_at, updated_at
            ) values (2, '待删除目录', 'Books', false, 'CLIENT_FOLDER', 60, current_timestamp, current_timestamp);
            insert into book_files (id, source_id, source_type, source_path, updated_at)
            values (10, 2, 'CLIENT_FOLDER', 'book.epub', current_timestamp)
            """.trimIndent(),
        ).update()

        fixture.service.deleteSource(2)

        assertEquals(
            0,
            fixture.jdbc.sql("select count(*) from library_sources where id = 2")
                .query(Int::class.java)
                .single(),
        )
        val detached = fixture.jdbc.sql(
            "select source_id, source_type, source_path from book_files where id = 10",
        ).query { rs, _ ->
            Triple(rs.getObject("source_id"), rs.getString("source_type"), rs.getString("source_path"))
        }.single()
        assertNull(detached.first)
        assertEquals("MANAGED_UPLOAD", detached.second)
        assertNull(detached.third)
    }

    private fun fixture(): Fixture {
        val dataSource = DriverManagerDataSource(
            "jdbc:h2:mem:${System.nanoTime()};MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
            "sa",
            "",
        )
        val jdbc = JdbcClient.create(dataSource)
        jdbc.sql(
            """
            create table library_sources (
                id bigint primary key,
                name varchar(255) not null,
                root_path text not null,
                enabled boolean not null,
                source_type varchar(64) not null,
                base_url text,
                remote_path text,
                username varchar(255),
                password text,
                scan_interval_minutes integer not null,
                last_scan_at timestamp with time zone,
                created_at timestamp with time zone not null,
                updated_at timestamp with time zone not null
            );
            create table library_source_files (
                source_id bigint not null references library_sources(id) on delete cascade,
                relative_path text not null,
                file_size bigint not null,
                last_modified_millis bigint not null,
                client_signature varchar(160) not null,
                updated_at timestamp with time zone not null,
                primary key (source_id, relative_path)
            );
            create table book_files (
                id bigint primary key,
                source_id bigint,
                source_type varchar(64) not null,
                source_path text,
                updated_at timestamp with time zone not null
            )
            """.trimIndent(),
        ).update()
        val bookService = mock<BookService>()
        return Fixture(
            jdbc = jdbc,
            bookService = bookService,
            service = LibrarySourceService(jdbc, bookService, AppProperties()),
        )
    }

    private data class Fixture(
        val jdbc: JdbcClient,
        val bookService: BookService,
        val service: LibrarySourceService,
    )
}
