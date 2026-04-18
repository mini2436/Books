package com.privatereader.books

import com.privatereader.auth.UserPrincipal
import jakarta.validation.Valid
import org.springframework.http.MediaType
import org.springframework.security.access.prepost.PreAuthorize
import org.springframework.security.core.annotation.AuthenticationPrincipal
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
    @PostMapping("/upload", consumes = [MediaType.MULTIPART_FORM_DATA_VALUE])
    fun uploadBook(
        @RequestPart("file") file: MultipartFile,
        @AuthenticationPrincipal actor: UserPrincipal,
    ): BookDetailView = bookService.uploadBook(file, actor)

    @PostMapping("/{bookId}/grants")
    fun grantBook(
        @PathVariable bookId: Long,
        @Valid @RequestBody request: CreateGrantRequest,
        @AuthenticationPrincipal actor: UserPrincipal,
    ): Map<String, Any> {
        bookService.grantBook(bookId, request.userId, actor.id)
        return mapOf("success" to true)
    }

    @GetMapping("/import-jobs")
    @PreAuthorize("hasAnyRole('SUPER_ADMIN','LIBRARIAN')")
    fun listImportJobs(): List<Map<String, Any?>> = bookService.listImportJobs()
}

