package com.privatereader.books

import com.privatereader.auth.UserPrincipal
import org.springframework.core.io.Resource
import org.springframework.http.HttpHeaders
import org.springframework.http.MediaType
import org.springframework.http.ResponseEntity
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/me/books")
class ReaderBookController(
    private val bookService: BookService,
) {
    @GetMapping
    fun listMyBooks(@AuthenticationPrincipal principal: UserPrincipal): List<BookView> =
        bookService.listAccessibleBooks(principal.id)

    @GetMapping("/{bookId}")
    fun getBook(
        @AuthenticationPrincipal principal: UserPrincipal,
        @PathVariable bookId: Long,
    ): BookDetailView = bookService.getAccessibleBook(principal.id, bookId)

    @GetMapping("/{bookId}/content-manifest")
    fun getContentManifest(
        @AuthenticationPrincipal principal: UserPrincipal,
        @PathVariable bookId: Long,
    ): Map<String, Any>? = bookService.getContentManifest(principal.id, bookId)

    @GetMapping("/{bookId}/file")
    fun downloadFile(
        @AuthenticationPrincipal principal: UserPrincipal,
        @PathVariable bookId: Long,
    ): ResponseEntity<Resource> {
        val resource = bookService.getBookFile(principal.id, bookId)
        return ResponseEntity.ok()
            .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename=\"${resource.filename}\"")
            .contentType(bookService.resolveMediaType(bookId))
            .body(resource)
    }

    @GetMapping("/{bookId}/cover")
    fun downloadCover(
        @AuthenticationPrincipal principal: UserPrincipal,
        @PathVariable bookId: Long,
    ): ResponseEntity<Resource> {
        val cover = bookService.getBookCover(principal.id, bookId)
            ?: return ResponseEntity.noContent().build()
        return ResponseEntity.ok()
            .contentType(MediaType.parseMediaType(cover.mimeType))
            .body(cover.resource)
    }
}
