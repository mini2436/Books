package com.privatereader.books

import com.privatereader.auth.UserPrincipal
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.mockito.kotlin.mock
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever

class AdminBookControllerBulkActionsTest {
    private lateinit var bookService: BookService
    private lateinit var controller: AdminBookController

    private val actor = UserPrincipal(7, "librarian", "LIBRARIAN")

    @BeforeEach
    fun setUp() {
        bookService = mock()
        controller = AdminBookController(bookService)
    }

    @Test
    fun `bulk grant assigns all selected books to user`() {
        whenever(bookService.grantBooks(listOf(3, 5, 8), 12, actor.id)).thenReturn(3)

        val response = controller.bulkGrantBooks(
            BulkGrantBooksRequest(bookIds = listOf(3, 5, 8), userId = 12),
            actor,
        )

        assertEquals(true, response["success"])
        assertEquals(3, response["grantedCount"])
        verify(bookService).grantBooks(listOf(3, 5, 8), 12, actor.id)
    }

    @Test
    fun `bulk group updates all selected books`() {
        whenever(bookService.updateAdminBookGroups(listOf(2, 4), "科幻")).thenReturn(2)

        val response = controller.bulkUpdateBookGroup(
            BulkUpdateBookGroupRequest(bookIds = listOf(2, 4), groupName = "科幻"),
        )

        assertEquals(true, response["success"])
        assertEquals(2, response["updatedCount"])
        verify(bookService).updateAdminBookGroups(listOf(2, 4), "科幻")
    }
}
