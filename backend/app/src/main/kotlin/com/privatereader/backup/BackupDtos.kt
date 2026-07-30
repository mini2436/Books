package com.privatereader.backup

enum class BackupScope { FULL, BOOKS, USER_DATA }

enum class BackupOrigin { MANUAL, SCHEDULED }

enum class BackupFrequency { WEEKLY, MONTHLY }

enum class UserDataType {
    BOOK_ACCESS,
    BOOK_GROUPS,
    ANNOTATIONS,
    BOOKMARKS,
    READING_HISTORY,
    READING_PROGRESS,
}

data class BackupExportRequest(
    val scope: BackupScope = BackupScope.FULL,
    val userIds: Set<Long> = emptySet(),
    val bookIds: Set<Long> = emptySet(),
    val dataTypes: Set<UserDataType> = emptySet(),
)

data class BackupDownloadTicketView(
    val downloadPath: String,
    val expiresAt: String,
)

data class BackupRecordView(
    val id: String,
    val scope: BackupScope,
    val origin: BackupOrigin,
    val filename: String,
    val sizeBytes: Long,
    val createdAt: String,
)

data class BackupScheduleView(
    val enabled: Boolean,
    val frequency: BackupFrequency,
    val lastRunAt: String? = null,
    val nextRunAt: String? = null,
    val updatedAt: String,
)

data class BackupScheduleUpdateRequest(
    val enabled: Boolean,
    val frequency: BackupFrequency = BackupFrequency.WEEKLY,
)

enum class UserDataRestoreMode { MERGE, REPLACE }

data class BackupUserView(
    val id: Long,
    val username: String,
    val displayName: String? = null,
)

data class BackupPreviewView(
    val formatVersion: Int,
    val scope: BackupScope,
    val createdAt: String,
    val sourceUsers: List<BackupUserView>,
    val books: Int,
    val annotations: Int,
    val bookmarks: Int,
    val histories: Int = 0,
    val progresses: Int,
    val dataTypes: Set<UserDataType> = emptySet(),
)

/**
 * The archive defines what can be restored; this request defines what the
 * administrator actually wants to restore from it. Source account IDs are
 * never trusted and only explicitly mapped users are restored.
 */
data class BackupRestoreRequest(
    val scope: BackupScope,
    val userMappings: Map<Long, Long> = emptyMap(),
    val mode: UserDataRestoreMode = UserDataRestoreMode.MERGE,
    val dataTypes: Set<UserDataType> = emptySet(),
)

data class BackupRestoreResult(
    val scope: BackupScope,
    val restoredUsers: Int,
    val restoredBooks: Int,
    val annotations: Int,
    val bookmarks: Int,
    val progresses: Int,
    val histories: Int = 0,
    val skippedBooks: Int = 0,
)

enum class FullRestorePhase { VALIDATING, DATABASE, FILES, FINALIZING, COMPLETED, FAILED }

data class FullRestoreStatusView(
    val operationId: String,
    val phase: FullRestorePhase,
    val percent: Int,
    val current: Int = 0,
    val total: Int = 0,
    val message: String,
    val updatedAt: String,
)
