package com.privatereader.backup

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

class BackupDownloadTicketServiceTest {
    @Test
    fun `ticket is opaque and can only be consumed once`() {
        val service = BackupDownloadTicketService()
        val request = BackupExportRequest(scope = BackupScope.BOOKS, bookIds = setOf(7, 9))

        val issued = service.issue(actorId = 1, request = request)
        val ticket = issued.downloadPath.substringAfterLast('/')

        assertEquals(request, service.consume(ticket))
        assertThrows(IllegalArgumentException::class.java) { service.consume(ticket) }
    }
}
