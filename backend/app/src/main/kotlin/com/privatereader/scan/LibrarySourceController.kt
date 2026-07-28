package com.privatereader.scan

import com.privatereader.auth.RoleExpressions
import com.privatereader.books.CreateLibrarySourceRequest
import com.privatereader.books.ClientLibraryScanPlanRequest
import com.privatereader.books.ClientLibraryScanPlanView
import com.privatereader.books.LibrarySourceView
import com.privatereader.books.UpdateLibrarySourceRequest
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
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.multipart.MultipartFile

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

    // 删除扫描任务但保留已经导入的图书，仅解除书籍与扫描源的关联。
    @DeleteMapping("/{sourceId}")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun deleteSource(@PathVariable sourceId: Long): Map<String, Any> {
        librarySourceService.deleteSource(sourceId)
        return mapOf("success" to true, "sourceId" to sourceId)
    }

    // 扫描源手动扫描接口：管理员或馆员立即触发指定扫描源导入。
    @PostMapping("/{sourceId}/rescan")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun rescan(@PathVariable sourceId: Long): Map<String, Any> = librarySourceService.scanSource(sourceId)

    // 客户端目录先上传轻量文件摘要，服务端只返回新增或变化后需要上传的相对路径。
    @PostMapping("/{sourceId}/client-scan/plan")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun planClientScan(
        @PathVariable sourceId: Long,
        @Valid @RequestBody request: ClientLibraryScanPlanRequest,
    ): ClientLibraryScanPlanView = librarySourceService.planClientScan(sourceId, request)

    // 客户端按扫描计划上传变化文件，服务端将文件托管后进入现有图书导入流程。
    @PostMapping("/{sourceId}/client-files", consumes = [MediaType.MULTIPART_FORM_DATA_VALUE])
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun uploadClientFile(
        @PathVariable sourceId: Long,
        @RequestParam("relativePath") relativePath: String,
        @RequestParam("sizeBytes") sizeBytes: Long,
        @RequestParam("lastModifiedMillis") lastModifiedMillis: Long,
        @RequestParam("file") file: MultipartFile,
        @AuthenticationPrincipal actor: UserPrincipal,
    ): Map<String, Any> = librarySourceService.uploadClientFile(
        sourceId = sourceId,
        relativePath = relativePath,
        sizeBytes = sizeBytes,
        lastModifiedMillis = lastModifiedMillis,
        file = file,
        actorId = actor.id,
    )

    // 大文件按固定大小分块上传，避免浏览器或中间网络设备重置超大的单次请求。
    @PostMapping("/{sourceId}/client-file-chunks", consumes = [MediaType.MULTIPART_FORM_DATA_VALUE])
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun uploadClientFileChunk(
        @PathVariable sourceId: Long,
        @RequestParam("relativePath") relativePath: String,
        @RequestParam("sizeBytes") sizeBytes: Long,
        @RequestParam("lastModifiedMillis") lastModifiedMillis: Long,
        @RequestParam("offsetBytes") offsetBytes: Long,
        @RequestParam("file") file: MultipartFile,
        @AuthenticationPrincipal actor: UserPrincipal,
    ): Map<String, Any> = librarySourceService.uploadClientFileChunk(
        sourceId = sourceId,
        relativePath = relativePath,
        sizeBytes = sizeBytes,
        lastModifiedMillis = lastModifiedMillis,
        offsetBytes = offsetBytes,
        file = file,
        actorId = actor.id,
    )
}
