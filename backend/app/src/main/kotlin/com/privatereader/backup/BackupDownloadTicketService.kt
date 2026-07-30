package com.privatereader.backup

import org.springframework.stereotype.Service
import org.springframework.scheduling.annotation.Scheduled
import java.nio.file.Files
import java.nio.file.Path
import java.time.Duration
import java.time.Instant
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

@Service
class BackupDownloadTicketService {
    private val tickets = ConcurrentHashMap<String, Ticket>()

    fun issue(actorId: Long, archivePath: Path, filename: String): BackupDownloadTicketView {
        removeExpired()
        val id = UUID.randomUUID().toString()
        val expiresAt = Instant.now().plus(TICKET_LIFETIME)
        tickets[id] = Ticket(
            actorId = actorId,
            archivePath = archivePath,
            filename = filename,
            expiresAt = expiresAt,
        )
        return BackupDownloadTicketView(
            downloadPath = "/api/admin/backups/download/$id",
            expiresAt = expiresAt.toString(),
        )
    }

    fun resolve(id: String): PreparedBackupDownload {
        require(id.matches(TICKET_PATTERN)) { "Invalid backup download ticket" }
        val ticket = tickets[id] ?: throw IllegalArgumentException("Backup download ticket was not found")
        if (!ticket.expiresAt.isAfter(Instant.now())) {
            tickets.remove(id, ticket)
            runCatching { Files.deleteIfExists(ticket.archivePath) }
            throw IllegalArgumentException("Backup download ticket has expired")
        }
        require(Files.isRegularFile(ticket.archivePath)) { "Prepared backup archive was not found" }
        return PreparedBackupDownload(ticket.archivePath, ticket.filename, ticket.expiresAt)
    }

    @Scheduled(fixedDelayString = "\${app.scheduler.backup-ticket-cleanup-ms:3600000}")
    private fun removeExpired() {
        val now = Instant.now()
        tickets.entries.removeIf { entry ->
            val expired = !entry.value.expiresAt.isAfter(now)
            if (expired) runCatching { Files.deleteIfExists(entry.value.archivePath) }
            expired
        }
    }

    private data class Ticket(
        val actorId: Long,
        val archivePath: Path,
        val filename: String,
        val expiresAt: Instant,
    )

    private companion object {
        val TICKET_LIFETIME: Duration = Duration.ofHours(24)
        val TICKET_PATTERN = Regex("[a-f0-9-]{36}")
    }
}

data class PreparedBackupDownload(
    val archivePath: Path,
    val filename: String,
    val expiresAt: Instant,
)
