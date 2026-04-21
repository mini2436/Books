package com.privatereader.books

import com.privatereader.auth.UserPrincipal
import jakarta.validation.Valid
import org.springframework.http.MediaType
import org.springframework.security.access.prepost.PreAuthorize
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PatchMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestPart
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.multipart.MultipartFile

@RestController
@RequestMapping("/api/admin/books")
class AdminBookController(
    private val bookService: BookService,
) {
    @GetMapping
    @PreAuthorize("hasAnyRole('SUPER_ADMIN','LIBRARIAN')")
    fun listBooks(): List<AdminBookView> = bookService.listAdminBooks()

    @GetMapping("/{bookId}")
    @PreAuthorize("hasAnyRole('SUPER_ADMIN','LIBRARIAN')")
    fun getBook(@PathVariable bookId: Long): AdminBookDetailView =
        bookService.getAdminBookDetail(bookId)

    @PostMapping("/upload", consumes = [MediaType.MULTIPART_FORM_DATA_VALUE])
    fun uploadBook(
        @RequestPart("file") file: MultipartFile,
        @AuthenticationPrincipal actor: UserPrincipal,
    ): BookDetailView = bookService.uploadBook(file, actor)

    @PatchMapping("/{bookId}")
    @PreAuthorize("hasAnyRole('SUPER_ADMIN','LIBRARIAN')")
    fun updateBook(
        @PathVariable bookId: Long,
        @RequestBody request: UpdateAdminBookRequest,
    ): AdminBookDetailView = bookService.updateAdminBook(bookId, request)

    @PostMapping("/bulk-delete")
    @PreAuthorize("hasAnyRole('SUPER_ADMIN','LIBRARIAN')")
    fun bulkDeleteBooks(
        @Valid @RequestBody request: BulkDeleteBooksRequest,
    ): Map<String, Any> {
        val deletedCount = bookService.deleteBooks(request.bookIds)
        return mapOf(
            "success" to true,
            "deletedCount" to deletedCount,
        )
    }

    @PostMapping("/{bookId}/grants")
    fun grantBook(
        @PathVariable bookId: Long,
        @Valid @RequestBody request: CreateGrantRequest,
        @AuthenticationPrincipal actor: UserPrincipal,
    ): Map<String, Any> {
        bookService.grantBook(bookId, request.userId, actor.id)
        return mapOf("success" to true)
    }

    @GetMapping("/{bookId}/viewers")
    @PreAuthorize("hasAnyRole('SUPER_ADMIN','LIBRARIAN')")
    fun listBookViewers(@PathVariable bookId: Long): List<BookViewerView> =
        bookService.listBookViewers(bookId)

    @DeleteMapping("/{bookId}/grants/{userId}")
    @PreAuthorize("hasAnyRole('SUPER_ADMIN','LIBRARIAN')")
    fun revokeBookGrant(
        @PathVariable bookId: Long,
        @PathVariable userId: Long,
    ): Map<String, Any> {
        bookService.revokeBookGrant(bookId, userId)
        return mapOf("success" to true)
    }

    @GetMapping("/grantable-users")
    @PreAuthorize("hasAnyRole('SUPER_ADMIN','LIBRARIAN')")
    fun listGrantableUsers(): List<UserView> = bookService.listGrantableUsers()

    @GetMapping("/import-jobs")
    @PreAuthorize("hasAnyRole('SUPER_ADMIN','LIBRARIAN')")
    fun listImportJobs(): List<Map<String, Any?>> = bookService.listImportJobs()
}
