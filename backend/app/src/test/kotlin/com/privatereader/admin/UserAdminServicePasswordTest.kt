package com.privatereader.admin

import com.privatereader.auth.AuthRepository
import com.privatereader.auth.UserRecord
import com.privatereader.auth.UserRole
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.mockito.kotlin.any
import org.mockito.kotlin.argumentCaptor
import org.mockito.kotlin.mock
import org.mockito.kotlin.never
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.security.crypto.factory.PasswordEncoderFactories

class UserAdminServicePasswordTest {
    private val authRepository: AuthRepository = mock()
    private val jdbcClient: JdbcClient = mock()
    private val passwordEncoder = PasswordEncoderFactories.createDelegatingPasswordEncoder()
    private val userAdminService = UserAdminService(authRepository, jdbcClient, passwordEncoder)

    @Test
    fun `reset password updates a reader password`() {
        whenever(authRepository.findUserById(9)).thenReturn(user(UserRole.READER))

        userAdminService.resetUserPassword(9, ResetUserPasswordRequest("reader-new"))

        val hash = argumentCaptor<String>()
        verify(authRepository).updatePassword(org.mockito.kotlin.eq(9), hash.capture())
        assertTrue(passwordEncoder.matches("reader-new", hash.firstValue))
    }

    @Test
    fun `reset password refuses a super administrator target`() {
        whenever(authRepository.findUserById(1)).thenReturn(user(UserRole.SUPER_ADMIN))

        assertThrows(IllegalArgumentException::class.java) {
            userAdminService.resetUserPassword(1, ResetUserPasswordRequest("admin-new"))
        }

        verify(authRepository, never()).updatePassword(any(), any())
    }

    private fun user(role: UserRole) = UserRecord(
        id = if (role == UserRole.SUPER_ADMIN) 1 else 9,
        username = if (role == UserRole.SUPER_ADMIN) "admin" else "reader",
        passwordHash = "unused",
        role = role.value,
        enabled = true,
    )
}
