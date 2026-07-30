package com.privatereader.backup

import com.privatereader.auth.RoleExpressions
import com.privatereader.auth.UserPrincipal
import jakarta.validation.Valid
import org.springframework.core.io.FileSystemResource
import org.springframework.core.io.Resource
import org.springframework.http.HttpHeaders
import org.springframework.http.MediaType
import org.springframework.http.ResponseEntity
import org.springframework.security.access.prepost.PreAuthorize
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RequestPart
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.multipart.MultipartFile
import java.time.Instant

@RestController
@RequestMapping("/api/admin/backups")
@PreAuthorize(RoleExpressions.SUPER_ADMIN_ONLY)
class BackupController(
    private val backupService: BackupService,
    private val downloadTickets: BackupDownloadTicketService,
) {
    @GetMapping("/export")
    fun export(
        @RequestParam(defaultValue = "FULL") scope: BackupScope,
        @RequestParam(required = false) userIds: Set<Long>?,
        @RequestParam(required = false) bookIds: Set<Long>?,
        @RequestParam(required = false) dataTypes: Set<UserDataType>?,
    ): ResponseEntity<Resource> {
        val request = BackupExportRequest(
            scope = scope,
            userIds = userIds.orEmpty(),
            bookIds = bookIds.orEmpty(),
            dataTypes = dataTypes.orEmpty(),
        )
        val filename = "private-reader-${scope.name.lowercase()}-${Instant.now().toString().replace(':', '-')}.zip"
        val resource = FileSystemResource(backupService.exportToFile(request))
        return ResponseEntity.ok()
            .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"$filename\"")
            .header(HttpHeaders.CACHE_CONTROL, "private, no-store")
            .header(HttpHeaders.ACCEPT_RANGES, "bytes")
            .contentLength(resource.contentLength())
            .contentType(MediaType.parseMediaType("application/zip"))
            .body(resource)
    }

    @PostMapping("/export-ticket")
    fun createExportTicket(
        @AuthenticationPrincipal principal: UserPrincipal,
        @RequestBody request: BackupExportRequest,
    ): BackupDownloadTicketView {
        val filename = "private-reader-${request.scope.name.lowercase()}-${Instant.now().toString().replace(':', '-')}.zip"
        val archivePath = backupService.exportToFile(request)
        return try {
            downloadTickets.issue(principal.id, archivePath, filename)
        } catch (error: Exception) {
            java.nio.file.Files.deleteIfExists(archivePath)
            throw error
        }
    }

    /** Upload first to inspect identities, then submit the selected mappings to /restore. */
    @PostMapping("/preview", consumes = [MediaType.MULTIPART_FORM_DATA_VALUE])
    fun preview(@RequestPart("file") file: MultipartFile): BackupPreviewView = backupService.preview(file)

    @PostMapping("/restore", consumes = [MediaType.MULTIPART_FORM_DATA_VALUE])
    fun restore(
        @AuthenticationPrincipal principal: UserPrincipal,
        @RequestPart("file") file: MultipartFile,
        @Valid @RequestPart("request") request: BackupRestoreRequest,
        @RequestParam(required = false) operationId: String? = null,
    ): BackupRestoreResult = backupService.restore(file, principal.id, request, operationId)

    @GetMapping("/restore-status/{operationId}")
    fun restoreStatus(@org.springframework.web.bind.annotation.PathVariable operationId: String): FullRestoreStatusView =
        backupService.getRestoreStatus(operationId)
}
