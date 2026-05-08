package com.privatereader.auth

import com.privatereader.config.AppProperties
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Test
import org.mockito.kotlin.any
import org.mockito.kotlin.doNothing
import org.mockito.kotlin.eq
import org.mockito.kotlin.mock
import org.mockito.kotlin.never
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever
import org.springframework.security.crypto.factory.PasswordEncoderFactories

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
}
