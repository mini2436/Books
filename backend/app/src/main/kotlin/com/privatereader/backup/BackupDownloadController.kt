package com.privatereader.backup

import org.springframework.core.io.InputStreamResource
import org.springframework.http.HttpHeaders
import org.springframework.http.MediaType
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController
import java.io.FilterInputStream
import java.nio.file.Files
import java.time.Instant

@RestController
@RequestMapping("/api/admin/backups/download")
class BackupDownloadController(
    private val backupService: BackupService,
    private val downloadTickets: BackupDownloadTicketService,
) {
    @GetMapping("/{ticket}")
    fun download(@PathVariable ticket: String): ResponseEntity<InputStreamResource> {
        val request = downloadTickets.consume(ticket)
        val archive = backupService.exportToFile(request)
        val filename = "private-reader-${request.scope.name.lowercase()}-${Instant.now().toString().replace(':', '-')}.zip"
        return ResponseEntity.ok()
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
}
