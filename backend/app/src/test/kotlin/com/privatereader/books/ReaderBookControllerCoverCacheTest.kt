package com.privatereader.books

import com.privatereader.auth.UserPrincipal
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.mockito.kotlin.mock
import org.mockito.kotlin.whenever
import org.springframework.core.io.ByteArrayResource
import org.springframework.http.HttpHeaders
import org.springframework.http.HttpStatus

class ReaderBookControllerCoverCacheTest {
    private lateinit var bookService: BookService
    private lateinit var controller: ReaderBookController

    private val principal = UserPrincipal(7, "reader", "READER")
    private val bytes = byteArrayOf(1, 2, 3)

    @BeforeEach
    fun setUp() {
        bookService = mock()
        controller = ReaderBookController(bookService)
        whenever(bookService.getBookCover(7, 42)).thenReturn(
            BookService.BookCoverResource(
                mimeType = "image/jpeg",
                resource = ByteArrayResource(bytes),
                version = "12345",
            ),
        )
    }

    @Test
    fun `versioned cover is immutable and privately cacheable`() {
        val response = controller.downloadCover(principal, 42, "12345", null)

        assertEquals(HttpStatus.OK, response.statusCode)
        assertEquals("\"book-cover-42-12345\"", response.headers.getFirst(HttpHeaders.ETAG))
        val cacheControl = response.headers.cacheControl.orEmpty()
        assertTrue(cacheControl.contains("max-age=31536000"))
        assertTrue(cacheControl.contains("private"))
        assertTrue(cacheControl.contains("immutable"))
        assertArrayEquals(bytes, response.body?.inputStream?.readAllBytes())
    }

    @Test
    fun `matching etag returns not modified`() {
        val response = controller.downloadCover(
            principal,
            42,
            "12345",
            "\"book-cover-42-12345\"",
        )

        assertEquals(HttpStatus.NOT_MODIFIED, response.statusCode)
        assertEquals("\"book-cover-42-12345\"", response.headers.getFirst(HttpHeaders.ETAG))
        assertNull(response.body)
    }

    @Test
    fun `unversioned cover must revalidate`() {
        val response = controller.downloadCover(principal, 42, null, null)

        val cacheControl = response.headers.getFirst(HttpHeaders.CACHE_CONTROL).orEmpty()
        assertTrue(cacheControl.contains("no-cache"))
        assertTrue(cacheControl.contains("private"))
    }
}
