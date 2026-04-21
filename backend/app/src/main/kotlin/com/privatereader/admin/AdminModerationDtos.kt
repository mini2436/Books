package com.privatereader.admin

data class AdminAnnotationView(
    val id: Long,
    val userId: Long,
    val username: String,
    val bookId: Long,
    val bookTitle: String,
    val quoteText: String?,
    val noteText: String?,
    val color: String?,
    val anchor: String,
    val version: Int,
    val deleted: Boolean,
    val updatedAt: String,
)

data class AdminBookmarkView(
    val id: Long,
    val userId: Long,
    val username: String,
    val bookId: Long,
    val bookTitle: String,
    val location: String,
    val label: String?,
    val deleted: Boolean,
    val updatedAt: String,
)

data class UpdateAdminDeletedRequest(
    val deleted: Boolean,
)
