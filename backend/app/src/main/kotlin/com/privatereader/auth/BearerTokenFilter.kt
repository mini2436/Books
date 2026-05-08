package com.privatereader.auth

import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken
import org.springframework.security.core.authority.SimpleGrantedAuthority
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.stereotype.Component
import org.springframework.web.filter.OncePerRequestFilter

@Component
class BearerTokenFilter(
    private val tokenService: TokenService,
) : OncePerRequestFilter() {
    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain,
    ) {
        val header = request.getHeader("Authorization")
        if (header?.startsWith("Bearer ") == true) {
            val token = header.removePrefix("Bearer ").trim()
            val principal = tokenService.authenticateAccessToken(token)
            if (principal != null) {
                val authentication = UsernamePasswordAuthenticationToken(
                    principal,
                    token,
                    listOf(SimpleGrantedAuthority(RoleAuthorities.fromRole(principal.role))),
                )
                SecurityContextHolder.getContext().authentication = authentication
            }
        }
        filterChain.doFilter(request, response)
    }
}

