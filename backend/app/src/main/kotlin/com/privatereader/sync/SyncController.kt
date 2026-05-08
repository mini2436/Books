package com.privatereader.sync

import com.privatereader.auth.UserPrincipal
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@RestController
class SyncController(
    private val syncService: SyncService,
) {
    // 离线变更推送接口：接收批注、书签和阅读进度的本地变更。
    @PostMapping("/api/me/sync/push")
    fun push(
        @AuthenticationPrincipal principal: UserPrincipal,
        @RequestBody request: SyncPushRequest,
    ): SyncPushResponse = syncService.push(principal.id, request)

    // 增量同步拉取接口：按游标返回当前用户后续变化的数据。
    @GetMapping("/api/me/sync/pull")
    fun pull(
        @AuthenticationPrincipal principal: UserPrincipal,
        @RequestParam(required = false) cursor: Long?,
    ): SyncPullResponse = syncService.pull(principal.id, cursor)

    // 批注列表接口：查询当前用户在指定书籍下的批注。
    @GetMapping("/api/me/books/{bookId}/annotations")
    fun getAnnotations(
        @AuthenticationPrincipal principal: UserPrincipal,
        @PathVariable bookId: Long,
    ): List<AnnotationView> = syncService.getAnnotations(principal.id, bookId)

    // 书签列表接口：查询当前用户在指定书籍下的书签。
    @GetMapping("/api/me/books/{bookId}/bookmarks")
    fun getBookmarks(
        @AuthenticationPrincipal principal: UserPrincipal,
        @PathVariable bookId: Long,
    ): List<BookmarkView> = syncService.getBookmarks(principal.id, bookId)

    // 阅读进度接口：写入或更新当前用户在指定书籍上的阅读进度。
    @PutMapping("/api/me/books/{bookId}/progress")
    fun putProgress(
        @AuthenticationPrincipal principal: UserPrincipal,
        @PathVariable bookId: Long,
        @RequestBody request: ReadingProgressMutation,
    ): ReadingProgressView {
        require(request.bookId == bookId) { "Book id mismatch" }
        return syncService.upsertReadingProgress(principal.id, request)
    }
}
