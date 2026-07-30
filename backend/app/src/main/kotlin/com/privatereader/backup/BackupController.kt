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
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RequestPart
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.multipart.MultipartFile

@RestController
@RequestMapping("/api/admin/backups")
@PreAuthorize(RoleExpressions.SUPER_ADMIN_ONLY)
class BackupController(
    private val backupService: BackupService,
    private val backupHistoryService: BackupHistoryService,
    private val downloadTickets: BackupDownloadTicketService,
) {
    @GetMapping("/export")
    fun export(
        @AuthenticationPrincipal principal: UserPrincipal,
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
        return archiveResponse(backupHistoryService.createManualArchive(request, principal.id))
    }

    @PostMapping("/export-ticket")
    fun createExportTicket(
        @AuthenticationPrincipal principal: UserPrincipal,
        @RequestBody request: BackupExportRequest,
    ): BackupDownloadTicketView {
        val stored = backupHistoryService.createManualArchive(request, principal.id)
        return downloadTickets.issue(
            principal.id,
            stored.archivePath,
            stored.record.filename,
            deleteArchiveOnExpiry = false,
        )
    }

    @GetMapping("/records")
    fun listRecords(): List<BackupRecordView> = backupHistoryService.listRecords()

    @GetMapping("/records/{id}/download")
    fun downloadRecord(@PathVariable id: String): ResponseEntity<Resource> =
        archiveResponse(backupHistoryService.getStoredBackup(id))

    @PostMapping("/records/{id}/download-ticket")
    fun createRecordDownloadTicket(
        @AuthenticationPrincipal principal: UserPrincipal,
        @PathVariable id: String,
    ): BackupDownloadTicketView {
        val stored = backupHistoryService.getStoredBackup(id)
        return downloadTickets.issue(
            principal.id,
            stored.archivePath,
            stored.record.filename,
            deleteArchiveOnExpiry = false,
        )
    }

    @DeleteMapping("/records/{id}")
    fun deleteRecord(
        @PathVariable id: String,
        @RequestParam(defaultValue = "false") confirm: Boolean,
    ): Map<String, Boolean> {
        require(confirm) { "Backup deletion must be explicitly confirmed" }
        backupHistoryService.deleteRecord(id)
        return mapOf("deleted" to true)
    }

    @GetMapping("/schedule")
    fun getSchedule(): BackupScheduleView = backupHistoryService.getSchedule()

    @PutMapping("/schedule")
    fun updateSchedule(@RequestBody request: BackupScheduleUpdateRequest): BackupScheduleView =
        backupHistoryService.updateSchedule(request)

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

    private fun archiveResponse(stored: StoredBackup): ResponseEntity<Resource> {
        val resource = FileSystemResource(stored.archivePath)
        return ResponseEntity.ok()
            .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"${stored.record.filename}\"")
            .header(HttpHeaders.CACHE_CONTROL, "private, no-store")
            .header(HttpHeaders.ACCEPT_RANGES, "bytes")
            .contentLength(resource.contentLength())
            .contentType(MediaType.parseMediaType("application/zip"))
            .body(resource)
    }
}
