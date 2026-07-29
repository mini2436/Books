package com.privatereader.backup

import org.springframework.http.HttpHeaders
import org.springframework.http.MediaType
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody
import java.time.Instant

@RestController
@RequestMapping("/api/admin/backups/download")
class BackupDownloadController(
    private val backupService: BackupService,
    private val downloadTickets: BackupDownloadTicketService,
) {
    @GetMapping("/{ticket}")
    fun download(@PathVariable ticket: String): ResponseEntity<StreamingResponseBody> {
        val request = downloadTickets.consume(ticket)
        val filename = "private-reader-${request.scope.name.lowercase()}-${Instant.now().toString().replace(':', '-')}.zip"
        return ResponseEntity.ok()
            .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"$filename\"")
            .header(HttpHeaders.CACHE_CONTROL, "no-store")
            .header("X-Accel-Buffering", "no")
            .contentType(MediaType.parseMediaType("application/zip"))
            .body(StreamingResponseBody { output -> backupService.exportTo(request, output) })
    }
}
