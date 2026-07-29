package com.privatereader.backup

import org.springframework.stereotype.Service
import java.time.Duration
import java.time.Instant
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

@Service
class BackupDownloadTicketService {
    private val tickets = ConcurrentHashMap<String, Ticket>()

    fun issue(actorId: Long, request: BackupExportRequest): BackupDownloadTicketView {
        removeExpired()
        val id = UUID.randomUUID().toString()
        val expiresAt = Instant.now().plus(TICKET_LIFETIME)
        tickets[id] = Ticket(actorId = actorId, request = request, expiresAt = expiresAt)
        return BackupDownloadTicketView(
            downloadPath = "/api/admin/backups/download/$id",
            expiresAt = expiresAt.toString(),
        )
    }

    fun consume(id: String): BackupExportRequest {
        require(id.matches(TICKET_PATTERN)) { "Invalid backup download ticket" }
        val ticket = tickets.remove(id) ?: throw IllegalArgumentException("Backup download ticket was not found")
        require(ticket.expiresAt.isAfter(Instant.now())) { "Backup download ticket has expired" }
        return ticket.request
    }

    private fun removeExpired() {
        val now = Instant.now()
        tickets.entries.removeIf { !it.value.expiresAt.isAfter(now) }
    }

    private data class Ticket(
        val actorId: Long,
        val request: BackupExportRequest,
        val expiresAt: Instant,
    )

    private companion object {
        val TICKET_LIFETIME: Duration = Duration.ofMinutes(10)
        val TICKET_PATTERN = Regex("[a-f0-9-]{36}")
    }
}
