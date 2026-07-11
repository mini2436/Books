package com.privatereader.auth

import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size

data class LoginRequest(
    @field:NotBlank
    val username: String,
    @field:NotBlank
    val password: String,
)

data class RefreshRequest(
    @field:NotBlank
    val refreshToken: String,
)

data class AuthResponse(
    val accessToken: String,
    val refreshToken: String,
    val user: AuthUserView,
)

data class AuthUserView(
    val id: Long,
    val username: String,
    val displayName: String?,
    val role: String,
    val hasAvatar: Boolean,
    val avatarVersion: String?,
)

data class UpdateProfileRequest(
    @field:Size(max = 120)
    val displayName: String?,
)

