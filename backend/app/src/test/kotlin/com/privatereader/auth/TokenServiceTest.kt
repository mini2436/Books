package com.privatereader.auth

import com.privatereader.config.AppProperties
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import org.mockito.kotlin.any
import org.mockito.kotlin.doNothing
import org.mockito.kotlin.eq
import org.mockito.kotlin.mock
import org.mockito.kotlin.never
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever
import org.springframework.security.crypto.factory.PasswordEncoderFactories
import java.time.Instant

class TokenServiceTest {
    private val authRepository: AuthRepository = mock()
    private val passwordEncoder = PasswordEncoderFactories.createDelegatingPasswordEncoder()
    private val tokenService = TokenService(
        authRepository = authRepository,
        passwordEncoder = passwordEncoder,
        appProperties = AppProperties(),
    )

    @Test
    fun `login issues access and refresh tokens`() {
        whenever(authRepository.findUserByUsername("alice")).thenReturn(
            UserRecord(
                id = 1,
                username = "alice",
                passwordHash = passwordEncoder.encode("secret"),
                role = UserRole.READER.value,
                enabled = true,
            ),
        )
        doNothing().whenever(authRepository).createToken(any(), any(), any(), any(), any())

        val response = tokenService.login(LoginRequest(username = "alice", password = "secret"))

        assertEquals("alice", response.user.username)
        assertNotNull(response.accessToken)
        verify(authRepository).createToken(
            eq(1L),
            any(),
            any(),
            any(),
            any(),
        )
        verify(authRepository, never()).revokeToken(any())
    }

    @Test
    fun `expired access token does not revoke its refresh token`() {
        val expiredToken = TokenRecord(
            id = 7,
            userId = 1,
            accessTokenHash = "access-hash",
            refreshTokenHash = "refresh-hash",
            expiresAt = Instant.now().minusSeconds(1),
            refreshExpiresAt = Instant.now().plusSeconds(3600),
            revoked = false,
        )
        whenever(authRepository.findActiveTokenByAccessHash(any())).thenReturn(expiredToken)

        val principal = tokenService.authenticateAccessToken("expired-access-token")

        assertNull(principal)
        verify(authRepository, never()).revokeToken(expiredToken.id)
    }

    @Test
    fun `refresh rotates tokens after access token has expired`() {
        val user = UserRecord(
            id = 1,
            username = "alice",
            passwordHash = passwordEncoder.encode("secret"),
            role = UserRole.READER.value,
            enabled = true,
        )
        val token = TokenRecord(
            id = 8,
            userId = user.id,
            accessTokenHash = "expired-access-hash",
            refreshTokenHash = "refresh-hash",
            expiresAt = Instant.now().minusSeconds(1),
            refreshExpiresAt = Instant.now().plusSeconds(3600),
            revoked = false,
        )
        whenever(authRepository.findActiveTokenByRefreshHash(any())).thenReturn(token)
        whenever(authRepository.findUserById(user.id)).thenReturn(user)
        doNothing().whenever(authRepository).revokeToken(token.id)
        doNothing().whenever(authRepository).createToken(any(), any(), any(), any(), any())

        val refreshed = tokenService.refresh("still-valid-refresh-token")

        assertEquals("alice", refreshed.user.username)
        assertNotNull(refreshed.accessToken)
        assertNotNull(refreshed.refreshToken)
        verify(authRepository).revokeToken(token.id)
    }
}
