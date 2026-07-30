package com.privatereader.backup

import com.privatereader.config.AppProperties
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.mockito.kotlin.any
import org.mockito.kotlin.argumentCaptor
import org.mockito.kotlin.mock
import org.mockito.kotlin.times
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.jdbc.datasource.DriverManagerDataSource
import java.nio.file.Files
import java.nio.file.Path
import java.sql.Timestamp
import java.time.Instant

class BackupHistoryServiceTest {
    @TempDir
    lateinit var temporaryDirectory: Path

    private lateinit var backupService: BackupService
    private lateinit var jdbc: JdbcClient
    private lateinit var service: BackupHistoryService

    @BeforeEach
    fun setUp() {
        val dataSource = DriverManagerDataSource(
            "jdbc:h2:mem:backup-history-${System.nanoTime()};MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
            "sa",
            "",
        )
        jdbc = JdbcClient.create(dataSource)
        jdbc.sql("create table users (id bigint primary key)").update()
        jdbc.sql(
            """
            create table backup_schedule_settings (
                id integer primary key,
                enabled boolean not null default false,
                frequency varchar(16) not null default 'WEEKLY',
                last_run_at timestamp with time zone,
                next_run_at timestamp with time zone,
                updated_at timestamp with time zone not null
            )
            """.trimIndent(),
        ).update()
        jdbc.sql(
            """
            create table backup_records (
                id varchar(36) primary key,
                scope varchar(32) not null,
                origin varchar(32) not null,
                filename varchar(255) not null,
                storage_path text not null,
                file_size bigint not null,
                created_by bigint references users(id) on delete set null,
                created_at timestamp with time zone not null
            )
            """.trimIndent(),
        ).update()
        jdbc.sql("insert into users (id) values (1)").update()

        backupService = mock()
        whenever(backupService.exportToFile(any())).thenAnswer { invocation ->
            val request = invocation.getArgument<BackupExportRequest>(0)
            Files.createTempFile(temporaryDirectory, "prepared-", ".zip").also {
                Files.writeString(it, "archive-${request.scope.name}")
            }
        }
        service = BackupHistoryService(
            backupService,
            jdbc,
            AppProperties(storageRoot = temporaryDirectory.resolve("storage").toString()),
        )
    }

    @Test
    fun `schedule defaults to weekly and can be enabled monthly`() {
        val defaultSchedule = service.getSchedule()
        assertFalse(defaultSchedule.enabled)
        assertEquals(BackupFrequency.WEEKLY, defaultSchedule.frequency)

        val updated = service.updateSchedule(
            BackupScheduleUpdateRequest(enabled = true, frequency = BackupFrequency.MONTHLY),
        )

        assertTrue(updated.enabled)
        assertEquals(BackupFrequency.MONTHLY, updated.frequency)
        assertNotNull(updated.nextRunAt)
        assertTrue(Instant.parse(updated.nextRunAt).isAfter(Instant.now()))
    }

    @Test
    fun `manual archive is retained in history and cleanup removes its file`() {
        val stored = service.createManualArchive(BackupExportRequest(BackupScope.BOOKS), actorId = 1)

        assertTrue(Files.isRegularFile(stored.archivePath))
        val listed = service.listRecords().single()
        assertEquals(stored.record.id, listed.id)
        assertEquals(stored.record.scope, listed.scope)
        assertEquals(stored.record.filename, listed.filename)
        assertEquals(stored.record.sizeBytes, listed.sizeBytes)
        assertEquals(BackupOrigin.MANUAL, stored.record.origin)

        service.deleteRecord(stored.record.id)

        assertFalse(Files.exists(stored.archivePath))
        assertTrue(service.listRecords().isEmpty())
    }

    @Test
    fun `due schedule creates full books and all-user archives`() {
        service.updateSchedule(BackupScheduleUpdateRequest(enabled = true))
        jdbc.sql("update backup_schedule_settings set next_run_at = :due where id = 1")
            .param("due", Timestamp.from(Instant.now().minusSeconds(1)))
            .update()

        service.runDueScheduledBackups()

        val records = service.listRecords()
        assertEquals(3, records.size)
        assertEquals(BackupScope.entries.toSet(), records.map { it.scope }.toSet())
        assertTrue(records.all { it.origin == BackupOrigin.SCHEDULED })
        assertNotNull(service.getSchedule().lastRunAt)

        val requests = argumentCaptor<BackupExportRequest>()
        verify(backupService, times(3)).exportToFile(requests.capture())
        assertEquals(setOf(1L), requests.allValues.single { it.scope == BackupScope.USER_DATA }.userIds)
    }
}
