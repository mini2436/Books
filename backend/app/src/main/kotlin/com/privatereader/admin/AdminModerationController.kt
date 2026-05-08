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
    // 批注审核列表接口：管理员或馆员查看全站批注。
    @GetMapping("/annotations")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun listAnnotations(): List<AdminAnnotationView> = adminModerationService.listAnnotations()

    // 批注隐藏状态接口：管理员或馆员隐藏或恢复指定批注。
    @PatchMapping("/annotations/{annotationId}")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun updateAnnotationDeleted(
        @PathVariable annotationId: Long,
        @RequestBody request: UpdateAdminDeletedRequest,
    ): AdminAnnotationView = adminModerationService.updateAnnotationDeleted(annotationId, request.deleted)

    // 书签审核列表接口：管理员或馆员查看全站书签。
    @GetMapping("/bookmarks")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun listBookmarks(): List<AdminBookmarkView> = adminModerationService.listBookmarks()

    // 书签隐藏状态接口：管理员或馆员隐藏或恢复指定书签。
    @PatchMapping("/bookmarks/{bookmarkId}")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun updateBookmarkDeleted(
        @PathVariable bookmarkId: Long,
        @RequestBody request: UpdateAdminDeletedRequest,
    ): AdminBookmarkView = adminModerationService.updateBookmarkDeleted(bookmarkId, request.deleted)
}
