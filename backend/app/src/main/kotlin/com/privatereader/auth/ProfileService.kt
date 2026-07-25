package com.privatereader.auth

import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.stereotype.Service

@Service
class ProfileService(
    private val authRepository: AuthRepository,
    private val passwordEncoder: PasswordEncoder,
) {
    fun changePassword(userId: Long, request: ChangePasswordRequest) {
        val existing = authRepository.findUserById(userId)
            ?: throw IllegalArgumentException("User not found")
        require(passwordEncoder.matches(request.currentPassword, existing.passwordHash)) {
            "Current password is incorrect"
        }
        authRepository.updatePassword(userId, passwordEncoder.encode(request.newPassword))
    }
}
