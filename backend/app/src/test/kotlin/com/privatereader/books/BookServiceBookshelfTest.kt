package com.privatereader.books

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import com.privatereader.config.AppProperties
import com.privatereader.pluginruntime.PluginRegistryService
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.jdbc.datasource.DriverManagerDataSource

class BookServiceBookshelfTest {
    @Test
    fun `all roles require explicit grants and inherit admin group without overwriting personal group`() {
        val dataSource = DriverManagerDataSource(
            "jdbc:h2:mem:${System.nanoTime()};MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
            "sa",
            "",
        )
        val jdbcClient = JdbcClient.create(dataSource)
        jdbcClient.sql(
            """
            create table books (
                id bigint primary key,
                title varchar(255) not null,
                author varchar(255),
                group_name varchar(120),
                description text,
                cover_updated_at timestamp with time zone,
                updated_at timestamp with time zone not null
            );
            create table book_files (
                id bigint primary key,
                book_id bigint not null,
                plugin_id varchar(120) not null,
                format varchar(32) not null,
                source_type varchar(64) not null,
                source_missing boolean not null
            );
            create table user_book_groups (
                user_id bigint not null,
                book_id bigint not null,
                group_name varchar(120) not null,
                updated_at timestamp with time zone not null,
                primary key (user_id, book_id)
            );
            create table user_book_access (
                user_id bigint not null,
                book_id bigint not null,
                granted_by bigint not null,
                granted_at timestamp with time zone not null,
                primary key (user_id, book_id)
            )
            """.trimIndent(),
        ).update()
        jdbcClient.sql(
            """
            insert into books (id, title, author, group_name, description, updated_at)
            values (10, '测试书籍', '测试作者', '后台分组', null, current_timestamp);
            insert into book_files (id, book_id, plugin_id, format, source_type, source_missing)
            values (20, 10, 'epub', 'epub', 'MANAGED_UPLOAD', false);
            insert into user_book_groups (user_id, book_id, group_name, updated_at)
            values (1, 10, '我的分组', current_timestamp),
                   (2, 10, '我的分组', current_timestamp);
            insert into user_book_access (user_id, book_id, granted_by, granted_at)
            values (1, 10, 1, current_timestamp)
            """.trimIndent(),
        ).update()

        val pluginRegistryService = mock<PluginRegistryService>()
        val objectMapper = jacksonObjectMapper()
        val service = BookService(
            jdbcClient = jdbcClient,
            pluginRegistryService = pluginRegistryService,
            objectMapper = objectMapper,
            appProperties = AppProperties(),
            bookResourceStorageService = BookResourceStorageService(
                jdbcClient = jdbcClient,
                pluginRegistryService = pluginRegistryService,
                objectMapper = objectMapper,
            ),
        )

        val books = service.listAccessibleBooks(1)

        assertEquals(1, books.size)
        assertEquals("我的分组", books.single().groupName)
        assertEquals(0, service.listAccessibleBooks(3).size)

        service.grantBook(bookId = 10, userId = 3, grantedBy = 1)
        assertEquals("后台分组", service.listAccessibleBooks(3).single().groupName)

        service.grantBook(bookId = 10, userId = 2, grantedBy = 1)
        assertEquals(
            "我的分组",
            jdbcClient.sql("select group_name from user_book_groups where user_id = 2")
                .query(String::class.java)
                .single(),
        )

        assertEquals(1, service.grantBooks(bookIds = listOf(10), userId = 4, grantedBy = 1))
        assertEquals(
            "后台分组",
            jdbcClient.sql("select group_name from user_book_groups where user_id = 4")
                .query(String::class.java)
                .single(),
        )

        val renamed = service.renameAccessibleBookGroup(
            1,
            RenameBookGroupRequest(oldName = "我的分组", newName = "新分组"),
        )

        assertEquals(1, renamed.updatedBooks)
        assertEquals("新分组", service.listAccessibleBooks(1).single().groupName)
        assertEquals(
            "我的分组",
            jdbcClient.sql("select group_name from user_book_groups where user_id = 2")
                .query(String::class.java)
                .single(),
        )

        val regrouped = service.updateAccessibleBookGroups(
            1,
            BulkUpdateBookGroupRequest(bookIds = listOf(10), groupName = "批量分组"),
        )

        assertEquals(1, regrouped)
        assertEquals("批量分组", service.listAccessibleBooks(1).single().groupName)
        assertEquals(
            "我的分组",
            jdbcClient.sql("select group_name from user_book_groups where user_id = 2")
                .query(String::class.java)
                .single(),
        )
    }
}
