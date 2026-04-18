package com.privatereader.auth

data class UserPrincipal(
    val id: Long,
    val username: String,
    val role: String,
)

