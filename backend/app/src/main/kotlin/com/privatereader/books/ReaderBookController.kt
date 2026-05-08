package com.privatereader.books

import com.privatereader.auth.UserPrincipal
import org.springframework.core.io.Resource
import org.springframework.http.CacheControl
import org.springframework.http.ContentDisposition
import org.springframework.http.HttpHeaders
import org.springframework.http.MediaType
import org.springframework.http.ResponseEntity
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController
import java.nio.charset.StandardCharsets
import java.util.concurrent.TimeUnit

@RestController
@RequestMapping("/api/me/books")
class ReaderBookController(
    private val bookService: BookService,
) {
    // 我的书架接口：查询当前登录用户可访问的书籍列表。
    @GetMapping
    fun listMyBooks(@AuthenticationPrincipal principal: UserPrincipal): List<BookView> =
        bookService.listAccessibleBooks(principal.id)

    // 书籍详情接口：查询当前用户已授权书籍的元数据、阅读能力和结构化正文状态。
    @GetMapping("/{bookId}")
    fun getBook(
        @AuthenticationPrincipal principal: UserPrincipal,
        @PathVariable bookId: Long,
    ): BookDetailView = bookService.getAccessibleBook(principal.id, bookId)

    // 阅读清单接口：返回插件生成的 manifest，用于旧阅读器和导航入口。
    @GetMapping("/{bookId}/content-manifest")
    fun getContentManifest(
        @AuthenticationPrincipal principal: UserPrincipal,
        @PathVariable bookId: Long,
    ): Map<String, Any>? = bookService.getContentManifest(principal.id, bookId)

    // 结构化正文目录接口：返回统一正文版本和章节摘要列表。
    @GetMapping("/{bookId}/content")
    fun getStructuredContent(
        @AuthenticationPrincipal principal: UserPrincipal,
        @PathVariable bookId: Long,
    ): BookContentView = bookService.getStructuredContent(principal.id, bookId)

    // 结构化正文单章接口：按章节序号懒加载正文块。
    @GetMapping("/{bookId}/content/chapters/{chapterIndex}")
    fun getStructuredContentChapter(
        @AuthenticationPrincipal principal: UserPrincipal,
        @PathVariable bookId: Long,
        @PathVariable chapterIndex: Int,
    ): BookContentChapterView = bookService.getStructuredContentChapter(principal.id, bookId, chapterIndex)

    // 原始文件下载接口：返回当前用户已授权书籍的源文件流。
    @GetMapping("/{bookId}/file")
    fun downloadFile(
        @AuthenticationPrincipal principal: UserPrincipal,
        @PathVariable bookId: Long,
    ): ResponseEntity<Resource> {
        val resource = bookService.getBookFile(principal.id, bookId)
        return ResponseEntity.ok()
            .header(
                HttpHeaders.CONTENT_DISPOSITION,
                ContentDisposition.inline()
                    .filename(resource.filename ?: "book", StandardCharsets.UTF_8)
                    .build()
                    .toString(),
            )
            .contentType(bookService.resolveMediaType(bookId))
            .body(resource)
    }

    // 封面下载接口：返回书籍封面图片，无封面时返回 204。
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

    // 内容资源下载接口：返回正文中引用的图片等二进制资源。
    @GetMapping("/{bookId}/content/resources/{resourceId}")
    fun downloadContentResource(
        @AuthenticationPrincipal principal: UserPrincipal,
        @PathVariable bookId: Long,
        @PathVariable resourceId: String,
    ): ResponseEntity<Resource> {
        val resource = bookService.getBookResource(principal.id, bookId, resourceId)
            ?: return ResponseEntity.notFound().build()
        return ResponseEntity.ok()
            .cacheControl(CacheControl.maxAge(1, TimeUnit.DAYS).cachePrivate())
            .contentType(MediaType.parseMediaType(resource.mimeType))
            .body(resource.resource)
    }
}
