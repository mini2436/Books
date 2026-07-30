package com.privatereader.backup

import com.privatereader.config.AppProperties
import org.slf4j.LoggerFactory
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.dao.DuplicateKeyException
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Service
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.sql.Timestamp
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

@Service
class BackupHistoryService(
    private val backupService: BackupService,
    private val jdbcClient: JdbcClient,
    private val appProperties: AppProperties,
) {
    private val archiveLock = ReentrantLock()
    private val schedulerRunning = AtomicBoolean(false)

    fun createManualArchive(request: BackupExportRequest, actorId: Long): StoredBackup =
        createArchive(request, BackupOrigin.MANUAL, actorId)

    fun listRecords(): List<BackupRecordView> = jdbcClient.sql(
        """
        select id, scope, origin, filename, file_size, created_at
        from backup_records
        order by created_at desc, id desc
        """.trimIndent(),
    ).query { rs, _ ->
        BackupRecordView(
            id = rs.getString("id"),
            scope = BackupScope.valueOf(rs.getString("scope")),
            origin = BackupOrigin.valueOf(rs.getString("origin")),
            filename = rs.getString("filename"),
            sizeBytes = rs.getLong("file_size"),
            createdAt = rs.getTimestamp("created_at").toInstant().toString(),
        )
    }.list()

    fun getStoredBackup(id: String): StoredBackup {
        validateId(id)
        return jdbcClient.sql(
            """
            select id, scope, origin, filename, storage_path, file_size, created_at
            from backup_records where id = :id
            """.trimIndent(),
        ).param("id", id).query { rs, _ ->
            StoredBackup(
                record = BackupRecordView(
                    id = rs.getString("id"),
                    scope = BackupScope.valueOf(rs.getString("scope")),
                    origin = BackupOrigin.valueOf(rs.getString("origin")),
                    filename = rs.getString("filename"),
                    sizeBytes = rs.getLong("file_size"),
                    createdAt = rs.getTimestamp("created_at").toInstant().toString(),
                ),
                archivePath = checkedArchivePath(rs.getString("storage_path")),
            )
        }.optional().orElseThrow { IllegalArgumentException("Backup record was not found") }
            .also { require(Files.isRegularFile(it.archivePath)) { "Backup archive was not found" } }
    }

    fun deleteRecord(id: String) {
        val stored = getStoredBackup(id)
        Files.deleteIfExists(stored.archivePath)
        jdbcClient.sql("delete from backup_records where id = :id")
            .param("id", id)
            .update()
    }

    fun getSchedule(): BackupScheduleView {
        ensureScheduleRow()
        return jdbcClient.sql(
            """
            select enabled, frequency, last_run_at, next_run_at, updated_at
            from backup_schedule_settings where id = 1
            """.trimIndent(),
        ).query { rs, _ ->
            BackupScheduleView(
                enabled = rs.getBoolean("enabled"),
                frequency = BackupFrequency.valueOf(rs.getString("frequency")),
                lastRunAt = rs.getTimestamp("last_run_at")?.toInstant()?.toString(),
                nextRunAt = rs.getTimestamp("next_run_at")?.toInstant()?.toString(),
                updatedAt = rs.getTimestamp("updated_at").toInstant().toString(),
            )
        }.single()
    }

    fun updateSchedule(request: BackupScheduleUpdateRequest): BackupScheduleView {
        ensureScheduleRow()
        val now = Instant.now()
        val nextRunAt = if (request.enabled) nextRun(now, request.frequency) else null
        if (nextRunAt == null) {
            jdbcClient.sql(
                """
                update backup_schedule_settings
                set enabled = :enabled,
                    frequency = :frequency,
                    next_run_at = null,
                    updated_at = :updatedAt
                where id = 1
                """.trimIndent(),
            ).param("enabled", request.enabled)
                .param("frequency", request.frequency.name)
                .param("updatedAt", Timestamp.from(now))
                .update()
        } else {
            jdbcClient.sql(
                """
                update backup_schedule_settings
                set enabled = :enabled,
                    frequency = :frequency,
                    next_run_at = :nextRunAt,
                    updated_at = :updatedAt
                where id = 1
                """.trimIndent(),
            ).param("enabled", request.enabled)
                .param("frequency", request.frequency.name)
                .param("nextRunAt", Timestamp.from(nextRunAt))
                .param("updatedAt", Timestamp.from(now))
                .update()
        }
        return getSchedule()
    }

    @Scheduled(
        initialDelayString = "\${app.scheduler.backup-schedule-initial-delay-ms:30000}",
        fixedDelayString = "\${app.scheduler.backup-schedule-check-ms:60000}",
    )
    fun runDueScheduledBackups() {
        if (!schedulerRunning.compareAndSet(false, true)) return
        try {
            val now = Instant.now()
            if (!claimDueSchedule(now)) return
            val schedule = getSchedule()
            val createdIds = mutableListOf<String>()
            try {
                archiveLock.withLock {
                    createdIds += createArchiveUnlocked(
                        BackupExportRequest(scope = BackupScope.FULL),
                        BackupOrigin.SCHEDULED,
                        null,
                    ).record.id
                    createdIds += createArchiveUnlocked(
                        BackupExportRequest(scope = BackupScope.BOOKS),
                        BackupOrigin.SCHEDULED,
                        null,
                    ).record.id
                    val allUserIds = jdbcClient.sql("select id from users order by id")
                        .query(Long::class.java).list().toSet()
                    if (allUserIds.isNotEmpty()) {
                        createdIds += createArchiveUnlocked(
                            BackupExportRequest(scope = BackupScope.USER_DATA, userIds = allUserIds),
                            BackupOrigin.SCHEDULED,
                            null,
                        ).record.id
                    }
                }
                markScheduleCompleted(Instant.now(), schedule.frequency)
            } catch (error: Exception) {
                createdIds.forEach { id -> runCatching { deleteRecord(id) } }
                postponeScheduleAfterFailure(Instant.now())
                log.error("Scheduled backup batch failed", error)
            }
        } finally {
            schedulerRunning.set(false)
        }
    }

    private fun createArchive(
        request: BackupExportRequest,
        origin: BackupOrigin,
        actorId: Long?,
    ): StoredBackup = archiveLock.withLock { createArchiveUnlocked(request, origin, actorId) }

    private fun createArchiveUnlocked(
        request: BackupExportRequest,
        origin: BackupOrigin,
        actorId: Long?,
    ): StoredBackup {
        val id = UUID.randomUUID().toString()
        val createdAt = Instant.now()
        val filename = "private-reader-${request.scope.name.lowercase()}-${FILENAME_TIME.format(createdAt)}.zip"
        val archiveRoot = archiveRoot()
        Files.createDirectories(archiveRoot)
        val target = archiveRoot.resolve("$id.zip")
        val temporary = backupService.exportToFile(request)
        try {
            try {
                Files.move(temporary, target, StandardCopyOption.ATOMIC_MOVE)
            } catch (_: Exception) {
                Files.move(temporary, target, StandardCopyOption.REPLACE_EXISTING)
            }
            val size = Files.size(target)
            jdbcClient.sql(
                """
                insert into backup_records
                    (id, scope, origin, filename, storage_path, file_size, created_by, created_at)
                values
                    (:id, :scope, :origin, :filename, :storagePath, :fileSize, :createdBy, :createdAt)
                """.trimIndent(),
            ).param("id", id)
                .param("scope", request.scope.name)
                .param("origin", origin.name)
                .param("filename", filename)
                .param("storagePath", target.fileName.toString())
                .param("fileSize", size)
                .param("createdBy", actorId)
                .param("createdAt", Timestamp.from(createdAt))
                .update()
            return StoredBackup(
                BackupRecordView(id, request.scope, origin, filename, size, createdAt.toString()),
                target,
            )
        } catch (error: Exception) {
            Files.deleteIfExists(temporary)
            Files.deleteIfExists(target)
            throw error
        }
    }

    private fun claimDueSchedule(now: Instant): Boolean {
        ensureScheduleRow()
        return jdbcClient.sql(
            """
            update backup_schedule_settings
            set next_run_at = :retryAt, updated_at = :now
            where id = 1 and enabled = true and next_run_at is not null and next_run_at <= :now
            """.trimIndent(),
        ).param("retryAt", Timestamp.from(now.plus(SCHEDULE_FAILURE_RETRY_HOURS, ChronoUnit.HOURS)))
            .param("now", Timestamp.from(now))
            .update() == 1
    }

    private fun markScheduleCompleted(completedAt: Instant, frequency: BackupFrequency) {
        jdbcClient.sql(
            """
            update backup_schedule_settings
            set last_run_at = :lastRunAt, next_run_at = :nextRunAt, updated_at = :updatedAt
            where id = 1 and enabled = true
            """.trimIndent(),
        ).param("lastRunAt", Timestamp.from(completedAt))
            .param("nextRunAt", Timestamp.from(nextRun(completedAt, frequency)))
            .param("updatedAt", Timestamp.from(completedAt))
            .update()
    }

    private fun postponeScheduleAfterFailure(failedAt: Instant) {
        jdbcClient.sql(
            """
            update backup_schedule_settings
            set next_run_at = :nextRunAt, updated_at = :updatedAt
            where id = 1 and enabled = true
            """.trimIndent(),
        ).param("nextRunAt", Timestamp.from(failedAt.plus(SCHEDULE_FAILURE_RETRY_HOURS, ChronoUnit.HOURS)))
            .param("updatedAt", Timestamp.from(failedAt))
            .update()
    }

    private fun ensureScheduleRow() {
        try {
            jdbcClient.sql(
                """
                insert into backup_schedule_settings (id, enabled, frequency, updated_at)
                values (1, false, 'WEEKLY', :updatedAt)
                """.trimIndent(),
            ).param("updatedAt", Timestamp.from(Instant.now())).update()
        } catch (_: DuplicateKeyException) {
            // The singleton row already exists, including when another request won the startup race.
        }
    }

    private fun nextRun(from: Instant, frequency: BackupFrequency): Instant {
        val zoned = from.atZone(ZoneId.systemDefault())
        return when (frequency) {
            BackupFrequency.WEEKLY -> zoned.plusWeeks(1)
            BackupFrequency.MONTHLY -> zoned.plusMonths(1)
        }.toInstant()
    }

    private fun archiveRoot(): Path = Path.of(appProperties.storageRoot, "backups")
        .toAbsolutePath().normalize()

    private fun checkedArchivePath(raw: String): Path {
        val storedPath = Path.of(raw)
        val path = if (storedPath.isAbsolute) {
            storedPath.toAbsolutePath().normalize()
        } else {
            archiveRoot().resolve(storedPath).normalize()
        }
        require(path.startsWith(archiveRoot())) { "Invalid backup archive path" }
        return path
    }

    private fun validateId(id: String) {
        require(runCatching { UUID.fromString(id) }.isSuccess) { "Invalid backup record id" }
    }

    private companion object {
        val log = LoggerFactory.getLogger(BackupHistoryService::class.java)
        val FILENAME_TIME: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss")
            .withZone(ZoneId.systemDefault())
        const val SCHEDULE_FAILURE_RETRY_HOURS = 1L
    }
}

data class StoredBackup(
    val record: BackupRecordView,
    val archivePath: Path,
)
