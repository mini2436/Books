package com.privatereader.backup

import org.springframework.core.io.FileSystemResource
import org.springframework.core.io.Resource
import org.springframework.http.HttpHeaders
import org.springframework.http.MediaType
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/admin/backups/download")
class BackupDownloadController(
    private val downloadTickets: BackupDownloadTicketService,
) {
    @GetMapping("/{ticket}")
    fun download(@PathVariable ticket: String): ResponseEntity<Resource> {
        val prepared = downloadTickets.resolve(ticket)
        val resource = FileSystemResource(prepared.archivePath)
        return ResponseEntity.ok()
            .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"${prepared.filename}\"")
            .header(HttpHeaders.CACHE_CONTROL, "private, no-store")
            .header(HttpHeaders.ACCEPT_RANGES, "bytes")
            .contentLength(resource.contentLength())
            .contentType(MediaType.parseMediaType("application/zip"))
            .body(resource)
    }
}
