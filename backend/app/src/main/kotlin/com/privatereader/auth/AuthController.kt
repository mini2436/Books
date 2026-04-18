package com.privatereader.auth

import jakarta.validation.Valid
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/auth")
class AuthController(
    private val tokenService: TokenService,
) {
    @PostMapping("/login")
    fun login(@Valid @RequestBody request: LoginRequest): AuthResponse = tokenService.login(request)

    @PostMapping("/refresh")
    fun refresh(@Valid @RequestBody request: RefreshRequest): AuthResponse = tokenService.refresh(request.refreshToken)

    @PostMapping("/logout")
    fun logout(
        @RequestHeader("Authorization", required = false) authorization: String?,
        @AuthenticationPrincipal principal: UserPrincipal?,
    ): Map<String, Any> {
        if (principal != null && authorization?.startsWith("Bearer ") == true) {
            tokenService.revoke(authorization.removePrefix("Bearer ").trim())
        }
        return mapOf("success" to true)
    }
}

