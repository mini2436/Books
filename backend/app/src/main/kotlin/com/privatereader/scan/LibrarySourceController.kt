package com.privatereader.scan

import com.privatereader.auth.RoleExpressions
import com.privatereader.books.CreateLibrarySourceRequest
import com.privatereader.books.LibrarySourceView
import com.privatereader.books.UpdateLibrarySourceRequest
import jakarta.validation.Valid
import org.springframework.security.access.prepost.PreAuthorize
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PatchMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/admin/library-sources")
class LibrarySourceController(
    private val librarySourceService: LibrarySourceService,
) {
    // 扫描源列表接口：管理员或馆员查看全部书库扫描源配置。
    @GetMapping
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun listSources(): List<LibrarySourceView> = librarySourceService.listSources()

    // 扫描源创建接口：管理员或馆员新增本地文件夹或 WebDAV 扫描源。
    @PostMapping
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun createSource(@Valid @RequestBody request: CreateLibrarySourceRequest): LibrarySourceView =
        librarySourceService.createSource(request)

    // 扫描源更新接口：管理员或馆员修改指定扫描源配置。
    @PatchMapping("/{sourceId}")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun updateSource(
        @PathVariable sourceId: Long,
        @Valid @RequestBody request: UpdateLibrarySourceRequest,
    ): LibrarySourceView = librarySourceService.updateSource(sourceId, request)

    // 扫描源手动扫描接口：管理员或馆员立即触发指定扫描源导入。
    @PostMapping("/{sourceId}/rescan")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun rescan(@PathVariable sourceId: Long): Map<String, Any> = librarySourceService.scanSource(sourceId)
}
