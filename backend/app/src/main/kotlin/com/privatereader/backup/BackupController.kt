package com.privatereader.backup

import com.privatereader.auth.RoleExpressions
import com.privatereader.auth.UserPrincipal
import jakarta.validation.Valid
import org.springframework.core.io.InputStreamResource
import org.springframework.http.HttpHeaders
import org.springframework.http.MediaType
import org.springframework.security.access.prepost.PreAuthorize
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RequestPart
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.multipart.MultipartFile
import java.time.Instant
import java.io.FilterInputStream
import java.nio.file.Files

@RestController
@RequestMapping("/api/admin/backups")
@PreAuthorize(RoleExpressions.SUPER_ADMIN_ONLY)
class BackupController(
    private val backupService: BackupService,
) {
    @GetMapping("/export")
    fun export(
        @RequestParam(defaultValue = "FULL") scope: BackupScope,
        @RequestParam(required = false) userIds: Set<Long>?,
        @RequestParam(required = false) bookIds: Set<Long>?,
        @RequestParam(required = false) dataTypes: Set<UserDataType>?,
    ): org.springframework.http.ResponseEntity<InputStreamResource> {
        val archive = backupService.exportToFile(
            BackupExportRequest(
                scope = scope,
                userIds = userIds.orEmpty(),
                bookIds = bookIds.orEmpty(),
                dataTypes = dataTypes.orEmpty(),
            ),
        )
        val filename = "private-reader-${scope.name.lowercase()}-${Instant.now().toString().replace(':', '-')}.zip"
        return org.springframework.http.ResponseEntity.ok()
            .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"$filename\"")
            .contentType(MediaType.parseMediaType("application/zip"))
            .contentLength(Files.size(archive))
            .body(
                InputStreamResource(
                    object : FilterInputStream(Files.newInputStream(archive)) {
                        override fun close() {
                            try {
                                super.close()
                            } finally {
                                Files.deleteIfExists(archive)
                            }
                        }
                    },
                ),
            )
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
