package com.privatereader.admin

import org.springframework.security.access.prepost.PreAuthorize
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PatchMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/admin")
class AdminModerationController(
    private val adminModerationService: AdminModerationService,
) {
    @GetMapping("/annotations")
    @PreAuthorize("hasAnyRole('SUPER_ADMIN','LIBRARIAN')")
    fun listAnnotations(): List<AdminAnnotationView> = adminModerationService.listAnnotations()

    @PatchMapping("/annotations/{annotationId}")
    @PreAuthorize("hasAnyRole('SUPER_ADMIN','LIBRARIAN')")
    fun updateAnnotationDeleted(
        @PathVariable annotationId: Long,
        @RequestBody request: UpdateAdminDeletedRequest,
    ): AdminAnnotationView = adminModerationService.updateAnnotationDeleted(annotationId, request.deleted)

    @GetMapping("/bookmarks")
    @PreAuthorize("hasAnyRole('SUPER_ADMIN','LIBRARIAN')")
    fun listBookmarks(): List<AdminBookmarkView> = adminModerationService.listBookmarks()

    @PatchMapping("/bookmarks/{bookmarkId}")
    @PreAuthorize("hasAnyRole('SUPER_ADMIN','LIBRARIAN')")
    fun updateBookmarkDeleted(
        @PathVariable bookmarkId: Long,
        @RequestBody request: UpdateAdminDeletedRequest,
    ): AdminBookmarkView = adminModerationService.updateBookmarkDeleted(bookmarkId, request.deleted)
}
