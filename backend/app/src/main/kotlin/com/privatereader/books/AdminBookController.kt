package com.privatereader.books

import com.privatereader.auth.RoleExpressions
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
    // 后台书籍列表接口：管理员或馆员查看全部书籍。
    @GetMapping
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun listBooks(): List<AdminBookView> = bookService.listAdminBooks()

    // 后台书籍详情接口：管理员或馆员查看单本书的管理信息。
    @GetMapping("/{bookId}")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun getBook(@PathVariable bookId: Long): AdminBookDetailView =
        bookService.getAdminBookDetail(bookId)

    // 书籍上传接口：管理员或馆员上传文件并触发导入。
    @PostMapping("/upload", consumes = [MediaType.MULTIPART_FORM_DATA_VALUE])
    fun uploadBook(
        @RequestPart("file") file: MultipartFile,
        @AuthenticationPrincipal actor: UserPrincipal,
    ): BookDetailView = bookService.uploadBook(file, actor)

    // 书籍更新接口：管理员或馆员维护书籍分组等后台字段。
    @PatchMapping("/{bookId}")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun updateBook(
        @PathVariable bookId: Long,
        @RequestBody request: UpdateAdminBookRequest,
    ): AdminBookDetailView = bookService.updateAdminBook(bookId, request)

    // 结构化正文重建接口：管理员或馆员重新抽取指定书籍的统一正文。
    @PostMapping("/{bookId}/content/rebuild")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun rebuildStructuredContent(@PathVariable bookId: Long): AdminBookDetailView =
        bookService.rebuildStructuredContent(bookId)

    // 书籍批量删除接口：管理员或馆员一次删除多本书。
    @PostMapping("/bulk-delete")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun bulkDeleteBooks(
        @Valid @RequestBody request: BulkDeleteBooksRequest,
    ): Map<String, Any> {
        val deletedCount = bookService.deleteBooks(request.bookIds)
        return mapOf(
            "success" to true,
            "deletedCount" to deletedCount,
        )
    }

    // 书籍授权接口：管理员或馆员将指定书籍分配给用户。
    @PostMapping("/{bookId}/grants")
    fun grantBook(
        @PathVariable bookId: Long,
        @Valid @RequestBody request: CreateGrantRequest,
        @AuthenticationPrincipal actor: UserPrincipal,
    ): Map<String, Any> {
        bookService.grantBook(bookId, request.userId, actor.id)
        return mapOf("success" to true)
    }

    // 书籍可见用户接口：管理员或馆员查看一本书当前可见的用户列表。
    @GetMapping("/{bookId}/viewers")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun listBookViewers(@PathVariable bookId: Long): List<BookViewerView> =
        bookService.listBookViewers(bookId)

    // 解除书籍授权接口：管理员或馆员移除指定用户的显式授权。
    @DeleteMapping("/{bookId}/grants/{userId}")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun revokeBookGrant(
        @PathVariable bookId: Long,
        @PathVariable userId: Long,
    ): Map<String, Any> {
        bookService.revokeBookGrant(bookId, userId)
        return mapOf("success" to true)
    }

    // 可授权用户接口：管理员或馆员获取可被分配书籍的启用用户列表。
    @GetMapping("/grantable-users")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun listGrantableUsers(): List<UserView> = bookService.listGrantableUsers()

    // 导入任务接口：管理员或馆员查看最近的书籍导入记录。
    @GetMapping("/import-jobs")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun listImportJobs(): List<Map<String, Any?>> = bookService.listImportJobs()
}
