package com.privatereader.sync

data class AnnotationMutation(
    val clientTempId: String? = null,
    val annotationId: Long? = null,
    val bookId: Long,
    val action: String,
    val quoteText: String? = null,
    val noteText: String? = null,
    val color: String? = null,
    val anchor: String,
    val baseVersion: Int? = null,
    val updatedAt: String,
)

data class BookmarkMutation(
    val bookmarkId: Long? = null,
    val bookId: Long,
    val action: String,
    val location: String,
    val label: String? = null,
    val updatedAt: String,
)

data class ReadingProgressMutation(
    val bookId: Long,
    val location: String,
    val progressPercent: Double,
    val updatedAt: String,
)

data class SyncPushRequest(
    val annotations: List<AnnotationMutation> = emptyList(),
    val bookmarks: List<BookmarkMutation> = emptyList(),
    val progresses: List<ReadingProgressMutation> = emptyList(),
)

data class AnnotationView(
    val id: Long,
    val bookId: Long,
    val quoteText: String?,
    val noteText: String?,
    val color: String?,
    val anchor: String,
    val version: Int,
    val deleted: Boolean,
    val updatedAt: String,
)

data class BookmarkView(
    val id: Long,
    val bookId: Long,
    val location: String,
    val label: String?,
    val deleted: Boolean,
    val updatedAt: String,
)

data class ReadingProgressView(
    val bookId: Long,
    val location: String,
    val progressPercent: Double,
    val updatedAt: String,
)

data class SyncConflict(
    val entityType: String,
    val entityId: Long,
    val message: String,
    val serverAnnotation: AnnotationView? = null,
)

data class SyncPushResponse(
    val annotationMappings: Map<String, Long> = emptyMap(),
    val conflicts: List<SyncConflict> = emptyList(),
)

data class SyncPullResponse(
    val cursor: Long,
    val annotations: List<AnnotationView>,
    val bookmarks: List<BookmarkView>,
    val progresses: List<ReadingProgressView>,
)

