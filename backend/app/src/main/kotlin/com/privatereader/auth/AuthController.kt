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
    // 登录接口：校验用户名和密码，返回访问令牌、刷新令牌和当前用户信息。
    @PostMapping("/login")
    fun login(@Valid @RequestBody request: LoginRequest): AuthResponse = tokenService.login(request)

    // 刷新令牌接口：使用 refreshToken 换取新的访问令牌和刷新令牌。
    @PostMapping("/refresh")
    fun refresh(@Valid @RequestBody request: RefreshRequest): AuthResponse = tokenService.refresh(request.refreshToken)

    // 退出登录接口：撤销当前 Authorization 头中的访问令牌。
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

