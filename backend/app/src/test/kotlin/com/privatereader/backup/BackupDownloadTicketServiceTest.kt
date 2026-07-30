package com.privatereader.backup

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Files
import java.nio.file.Path

class BackupDownloadTicketServiceTest {
    @TempDir
    lateinit var temporaryDirectory: Path

    @Test
    fun `prepared archive ticket is opaque and reusable for range requests`() {
        val service = BackupDownloadTicketService()
        val archive = temporaryDirectory.resolve("backup.zip")
        Files.writeString(archive, "prepared archive")

        val issued = service.issue(actorId = 1, archivePath = archive, filename = "backup.zip")
        val ticket = issued.downloadPath.substringAfterLast('/')

        assertEquals(archive, service.resolve(ticket).archivePath)
        assertEquals("backup.zip", service.resolve(ticket).filename)
        assertEquals(archive, service.resolve(ticket).archivePath)
    }

    @Test
    fun `missing prepared archive is rejected`() {
        val service = BackupDownloadTicketService()
        val archive = temporaryDirectory.resolve("missing.zip")
        val issued = service.issue(actorId = 1, archivePath = archive, filename = "backup.zip")

        assertThrows(IllegalArgumentException::class.java) {
            service.resolve(issued.downloadPath.substringAfterLast('/'))
        }
    }
}
