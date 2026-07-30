package com.privatereader.backup

import org.hamcrest.Matchers.containsString
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.setup.MockMvcBuilders
import java.nio.file.Files
import java.nio.file.Path

class BackupDownloadControllerTest {
    @TempDir
    lateinit var temporaryDirectory: Path

    @Test
    fun `prepared backup supports content length and range downloads`() {
        val archive = temporaryDirectory.resolve("backup.zip")
        Files.write(archive, "0123456789".toByteArray())
        val tickets = BackupDownloadTicketService()
        val issued = tickets.issue(actorId = 1, archivePath = archive, filename = "backup.zip")
        val ticket = issued.downloadPath.substringAfterLast('/')
        val mockMvc = MockMvcBuilders.standaloneSetup(BackupDownloadController(tickets)).build()

        mockMvc.get("/api/admin/backups/download/$ticket") {
            header("Range", "bytes=3-6")
        }.andExpect {
            status { isPartialContent() }
            header { string("Accept-Ranges", "bytes") }
            header { string("Content-Range", "bytes 3-6/10") }
            header { string("Content-Length", "4") }
            header { string("Content-Disposition", containsString("backup.zip")) }
            content { bytes("3456".toByteArray()) }
        }
    }
}
