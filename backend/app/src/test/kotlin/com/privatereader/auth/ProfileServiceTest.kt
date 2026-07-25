package com.privatereader.auth

import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.mockito.kotlin.any
import org.mockito.kotlin.argumentCaptor
import org.mockito.kotlin.mock
import org.mockito.kotlin.never
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever
import org.springframework.security.crypto.factory.PasswordEncoderFactories

class ProfileServiceTest {
    private val authRepository: AuthRepository = mock()
    private val passwordEncoder = PasswordEncoderFactories.createDelegatingPasswordEncoder()
    private val profileService = ProfileService(authRepository, passwordEncoder)

    @Test
    fun `change password verifies the current password before updating`() {
        whenever(authRepository.findUserById(7)).thenReturn(reader(passwordEncoder.encode("old-secret")))

        profileService.changePassword(
            7,
            ChangePasswordRequest(currentPassword = "old-secret", newPassword = "new-secret"),
        )

        val hash = argumentCaptor<String>()
        verify(authRepository).updatePassword(org.mockito.kotlin.eq(7), hash.capture())
        assertTrue(passwordEncoder.matches("new-secret", hash.firstValue))
    }

    @Test
    fun `change password rejects an incorrect current password`() {
        whenever(authRepository.findUserById(7)).thenReturn(reader(passwordEncoder.encode("old-secret")))

        assertThrows(IllegalArgumentException::class.java) {
            profileService.changePassword(
                7,
                ChangePasswordRequest(currentPassword = "wrong", newPassword = "new-secret"),
            )
        }

        verify(authRepository, never()).updatePassword(any(), any())
    }

    private fun reader(passwordHash: String) = UserRecord(
        id = 7,
        username = "reader",
        passwordHash = passwordHash,
        role = UserRole.READER.value,
        enabled = true,
    )
}
