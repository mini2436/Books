package com.privatereader.auth

import com.privatereader.config.AppProperties
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.stereotype.Service
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.HexFormat
import java.util.UUID

@Service
class TokenService(
    private val authRepository: AuthRepository,
    private val passwordEncoder: PasswordEncoder,
    private val appProperties: AppProperties,
) {
    fun login(request: LoginRequest): AuthResponse {
        val user = authRepository.findUserByUsername(request.username)
            ?: throw IllegalArgumentException("Invalid username or password")
        require(user.enabled) { "User is disabled" }
        if (!passwordEncoder.matches(request.password, user.passwordHash)) {
            throw IllegalArgumentException("Invalid username or password")
        }
        return issueTokens(user)
    }

    fun refresh(refreshToken: String): AuthResponse {
        val refreshHash = digest(refreshToken)
        val tokenRecord = authRepository.findActiveTokenByRefreshHash(refreshHash)
            ?: throw IllegalArgumentException("Invalid refresh token")
        require(tokenRecord.refreshExpiresAt.isAfter(Instant.now())) { "Refresh token expired" }
        authRepository.revokeToken(tokenRecord.id)
        val user = authRepository.findUserById(tokenRecord.userId)
            ?: throw IllegalArgumentException("User no longer exists")
        return issueTokens(user)
    }

    fun authenticateAccessToken(accessToken: String): UserPrincipal? {
        val accessHash = digest(accessToken)
        val tokenRecord = authRepository.findActiveTokenByAccessHash(accessHash) ?: return null
        if (tokenRecord.expiresAt.isBefore(Instant.now())) {
            authRepository.revokeToken(tokenRecord.id)
            return null
        }
        val user = authRepository.findUserById(tokenRecord.userId) ?: return null
        if (!user.enabled) {
            authRepository.revokeToken(tokenRecord.id)
            return null
        }
        return UserPrincipal(id = user.id, username = user.username, role = user.role)
    }

    fun revoke(accessToken: String) {
        val record = authRepository.findActiveTokenByAccessHash(digest(accessToken)) ?: return
        authRepository.revokeToken(record.id)
    }

    fun bootstrapAdminIfNeeded() {
        if (authRepository.countUsers() > 0) {
            return
        }
        authRepository.insertUser(
            username = appProperties.bootstrapAdminUsername,
            passwordHash = passwordEncoder.encode(appProperties.bootstrapAdminPassword),
            role = "SUPER_ADMIN",
        )
    }

    private fun issueTokens(user: UserRecord): AuthResponse {
        val accessToken = UUID.randomUUID().toString() + UUID.randomUUID().toString()
        val refreshToken = UUID.randomUUID().toString() + UUID.randomUUID().toString()
        val now = Instant.now()
        authRepository.createToken(
            userId = user.id,
            accessTokenHash = digest(accessToken),
            refreshTokenHash = digest(refreshToken),
            expiresAt = now.plus(appProperties.accessTokenTtlMinutes, ChronoUnit.MINUTES),
            refreshExpiresAt = now.plus(appProperties.refreshTokenTtlDays, ChronoUnit.DAYS),
        )
        return AuthResponse(
            accessToken = accessToken,
            refreshToken = refreshToken,
            user = AuthUserView(id = user.id, username = user.username, role = user.role),
        )
    }

    private fun digest(raw: String): String {
        val bytes = MessageDigest.getInstance("SHA-256")
            .digest(raw.toByteArray(StandardCharsets.UTF_8))
        return HexFormat.of().formatHex(bytes)
    }
}

