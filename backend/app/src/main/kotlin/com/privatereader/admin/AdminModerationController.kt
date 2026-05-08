package com.privatereader.admin

import com.privatereader.auth.RoleExpressions
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
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun listAnnotations(): List<AdminAnnotationView> = adminModerationService.listAnnotations()

    @PatchMapping("/annotations/{annotationId}")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun updateAnnotationDeleted(
        @PathVariable annotationId: Long,
        @RequestBody request: UpdateAdminDeletedRequest,
    ): AdminAnnotationView = adminModerationService.updateAnnotationDeleted(annotationId, request.deleted)

    @GetMapping("/bookmarks")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun listBookmarks(): List<AdminBookmarkView> = adminModerationService.listBookmarks()

    @PatchMapping("/bookmarks/{bookmarkId}")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun updateBookmarkDeleted(
        @PathVariable bookmarkId: Long,
        @RequestBody request: UpdateAdminDeletedRequest,
    ): AdminBookmarkView = adminModerationService.updateBookmarkDeleted(bookmarkId, request.deleted)
}
