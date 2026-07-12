package com.privatereader.books

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import com.privatereader.auth.AuthRepository
import com.privatereader.auth.UserRecord
import com.privatereader.auth.UserRole
import com.privatereader.config.AppProperties
import com.privatereader.plugin.BookFormatPlugin
import com.privatereader.plugin.CoverExtractionResult
import com.privatereader.pluginruntime.PluginRegistryService
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.mockito.kotlin.any
import org.mockito.kotlin.mock
import org.mockito.kotlin.never
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.jdbc.datasource.DriverManagerDataSource
import java.nio.file.Files

class BookServiceCoverTest {
    private lateinit var jdbcClient: JdbcClient
    private lateinit var pluginRegistryService: PluginRegistryService
    private lateinit var authRepository: AuthRepository
    private lateinit var service: BookService

    @BeforeEach
    fun setUp() {
        val dataSource = DriverManagerDataSource(
            "jdbc:h2:mem:${System.nanoTime()};MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
            "sa",
            "",
        )
        jdbcClient = JdbcClient.create(dataSource)
        jdbcClient.sql(
            """
            create table books (
                id bigint primary key,
                cover_data bytea,
                cover_content_type varchar(100),
                cover_source_file_hash varchar(128),
                cover_updated_at timestamp with time zone
            )
            """.trimIndent(),
        ).update()
        jdbcClient.sql(
            """
            create table book_files (
                id bigint primary key,
                book_id bigint not null,
                storage_path text not null,
                plugin_id varchar(120) not null,
                format varchar(32) not null,
                file_hash varchar(128) not null
            )
            """.trimIndent(),
        ).update()
        jdbcClient.sql(
            """
            create table book_resources (
                book_id bigint not null,
                resource_id text not null,
                mime_type varchar(100) not null,
                resource_data bytea not null,
                source_file_hash varchar(128) not null,
                created_at timestamp with time zone not null,
                updated_at timestamp with time zone not null,
                primary key (book_id, resource_id)
            )
            """.trimIndent(),
        ).update()

        pluginRegistryService = mock()
        authRepository = mock()
        whenever(authRepository.findUserById(1)).thenReturn(
            UserRecord(
                id = 1,
                username = "admin",
                passwordHash = "unused",
                role = UserRole.SUPER_ADMIN.value,
                enabled = true,
            ),
        )
        val objectMapper = jacksonObjectMapper()
        val resourceStorageService = BookResourceStorageService(
            jdbcClient = jdbcClient,
            pluginRegistryService = pluginRegistryService,
            objectMapper = objectMapper,
        )
        service = BookService(
            jdbcClient = jdbcClient,
            pluginRegistryService = pluginRegistryService,
            objectMapper = objectMapper,
            appProperties = AppProperties(),
            authRepository = authRepository,
            bookResourceStorageService = resourceStorageService,
        )
    }

    @Test
    fun `returns stored cover without opening source file`() {
        val expected = byteArrayOf(1, 2, 3, 4)
        insertBook(10, "Z:/missing/book.epub", expected, "image/jpeg")

        val cover = service.getBookCover(1, 10)

        assertEquals("image/jpeg", cover?.mimeType)
        assertArrayEquals(expected, cover?.resource?.byteArray)
        verify(pluginRegistryService, never()).findPluginById(any())
    }

    @Test
    fun `extracts a missing cover once and stores it in database`() {
        val sourceFile = Files.createTempFile("reader-cover-cache", ".epub")
        val expected = byteArrayOf(9, 8, 7)
        insertBook(20, sourceFile.toString(), null, null)
        val plugin = mock<BookFormatPlugin>()
        whenever(pluginRegistryService.findPluginById("epub")).thenReturn(plugin)
        whenever(plugin.extractCover(sourceFile)).thenReturn(CoverExtractionResult("image/png", expected))

        val first = service.getBookCover(1, 20)
        val second = service.getBookCover(1, 20)

        assertArrayEquals(expected, first?.resource?.byteArray)
        assertArrayEquals(expected, second?.resource?.byteArray)
        assertEquals(
            "hash-20",
            jdbcClient.sql("select cover_source_file_hash from books where id = 20")
                .query(String::class.java)
                .single(),
        )
        verify(plugin).extractCover(sourceFile)
        Files.deleteIfExists(sourceFile)
    }

    @Test
    fun `returns stored body image without opening source epub`() {
        val expected = byteArrayOf(6, 5, 4, 3)
        insertBook(30, "Z:/missing/body-images.epub", null, null)
        jdbcClient.sql(
            """
            insert into book_resources (
                book_id, resource_id, mime_type, resource_data, source_file_hash, created_at, updated_at
            ) values (
                30, 'image-resource', 'image/png', :resourceData, 'hash-30', current_timestamp, current_timestamp
            )
            """.trimIndent(),
        )
            .param("resourceData", expected)
            .update()

        val resource = service.getBookResource(1, 30, "image-resource")

        assertEquals("image/png", resource?.mimeType)
        assertArrayEquals(expected, resource?.resource?.byteArray)
        verify(pluginRegistryService, never()).findPluginById(any())
    }

    private fun insertBook(
        bookId: Long,
        storagePath: String,
        coverData: ByteArray?,
        contentType: String?,
    ) {
        jdbcClient.sql(
            """
            insert into books (id, cover_data, cover_content_type)
            values (:bookId, :coverData, :contentType)
            """.trimIndent(),
        )
            .param("bookId", bookId)
            .param("coverData", coverData)
            .param("contentType", contentType)
            .update()
        jdbcClient.sql(
            """
            insert into book_files (id, book_id, storage_path, plugin_id, format, file_hash)
            values (:fileId, :bookId, :storagePath, 'epub', 'epub', :fileHash)
            """.trimIndent(),
        )
            .param("fileId", bookId)
            .param("bookId", bookId)
            .param("storagePath", storagePath)
            .param("fileHash", "hash-$bookId")
            .update()
    }
}
