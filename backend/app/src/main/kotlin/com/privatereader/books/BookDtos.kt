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
)

data class CreateGrantRequest(
    @field:NotNull
    val userId: Long,
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

