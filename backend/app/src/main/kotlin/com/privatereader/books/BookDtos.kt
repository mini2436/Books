package com.privatereader.books

import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotNull

data class BookView(
    val id: Long,
    val title: String,
    val author: String?,
    val description: String?,
    val pluginId: String,
    val format: String,
    val sourceType: String,
    val granted: Boolean,
    val sourceMissing: Boolean,
    val updatedAt: String,
)

data class BookDetailView(
    val id: Long,
    val title: String,
    val author: String?,
    val description: String?,
    val pluginId: String,
    val format: String,
    val sourceType: String,
    val manifest: Map<String, Any>?,
    val capabilities: Set<String>,
    val sourceMissing: Boolean,
    val hasStructuredContent: Boolean,
    val contentModel: String?,
    val latestContentVersionId: Long?,
)

data class AdminBookDetailView(
    val id: Long,
    val title: String,
    val author: String?,
    val groupName: String?,
    val description: String?,
    val pluginId: String,
    val format: String,
    val sourceType: String,
    val sourceMissing: Boolean,
    val hasStructuredContent: Boolean,
    val contentModel: String?,
    val latestContentVersionId: Long?,
    val updatedAt: String,
)

data class BookContentView(
    val bookId: Long,
    val contentModel: String?,
    val contentVersionId: Long?,
    val hasStructuredContent: Boolean,
    val chapters: List<BookContentChapterSummary>,
)

data class BookContentChapterSummary(
    val chapterIndex: Int,
    val title: String,
    val anchor: String,
)

data class BookContentChapterView(
    val bookId: Long,
    val contentModel: String,
    val contentVersionId: Long,
    val hasStructuredContent: Boolean,
    val chapterIndex: Int,
    val title: String,
    val anchor: String,
    val blocks: List<BookContentBlockView>,
)

data class BookContentBlockView(
    val blockIndex: Int,
    val type: String,
    val anchor: String,
    val text: String,
    val plainText: String,
    val meta: Map<String, Any?>,
)

data class AdminBookView(
    val id: Long,
    val title: String,
    val author: String?,
    val groupName: String?,
    val description: String?,
    val pluginId: String,
    val format: String,
    val sourceType: String,
    val sourceMissing: Boolean,
    val updatedAt: String,
)

data class CreateGrantRequest(
    @field:NotNull
    val userId: Long,
)

data class UpdateAdminBookRequest(
    val groupName: String? = null,
)

data class BulkDeleteBooksRequest(
    @field:NotNull
    val bookIds: List<Long>,
)

data class CreateLibrarySourceRequest(
    @field:NotBlank
    val name: String,
    @field:NotBlank
    val rootPath: String,
    val enabled: Boolean = true,
)

data class LibrarySourceView(
    val id: Long,
    val name: String,
    val rootPath: String,
    val enabled: Boolean,
    val lastScanAt: String?,
)

data class CreateUserRequest(
    @field:NotBlank
    val username: String,
    @field:NotBlank
    val password: String,
    @field:NotBlank
    val role: String,
)

data class UpdateUserRequest(
    val enabled: Boolean? = null,
    val role: String? = null,
)

data class UserView(
    val id: Long,
    val username: String,
    val role: String,
    val enabled: Boolean,
)

data class BookViewerView(
    val userId: Long,
    val username: String,
    val role: String,
    val enabled: Boolean,
    val accessSource: String,
    val grantedAt: String?,
)
