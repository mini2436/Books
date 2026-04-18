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
    @PostMapping("/api/me/sync/push")
    fun push(
        @AuthenticationPrincipal principal: UserPrincipal,
        @RequestBody request: SyncPushRequest,
    ): SyncPushResponse = syncService.push(principal.id, request)

    @GetMapping("/api/me/sync/pull")
    fun pull(
        @AuthenticationPrincipal principal: UserPrincipal,
        @RequestParam(required = false) cursor: Long?,
    ): SyncPullResponse = syncService.pull(principal.id, cursor)

    @GetMapping("/api/me/books/{bookId}/annotations")
    fun getAnnotations(
        @AuthenticationPrincipal principal: UserPrincipal,
        @PathVariable bookId: Long,
    ): List<AnnotationView> = syncService.getAnnotations(principal.id, bookId)

    @GetMapping("/api/me/books/{bookId}/bookmarks")
    fun getBookmarks(
        @AuthenticationPrincipal principal: UserPrincipal,
        @PathVariable bookId: Long,
    ): List<BookmarkView> = syncService.getBookmarks(principal.id, bookId)

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
