package com.privatereader.config

import com.privatereader.auth.BearerTokenFilter
import com.privatereader.auth.UserRole
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.security.config.Customizer
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.config.http.SessionCreationPolicy
import org.springframework.security.web.SecurityFilterChain
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter

@Configuration(proxyBeanMethods = false)
@EnableMethodSecurity
class SecurityConfig(
    private val bearerTokenFilter: BearerTokenFilter,
) {
    @Bean
    fun securityFilterChain(http: HttpSecurity): SecurityFilterChain {
        http
            .csrf { it.disable() }
            .cors(Customizer.withDefaults())
            .sessionManagement { it.sessionCreationPolicy(SessionCreationPolicy.STATELESS) }
            .authorizeHttpRequests {
                it.requestMatchers("/actuator/health", "/api/auth/login", "/api/auth/refresh", "/error").permitAll()
                    .requestMatchers("/api/admin/**").hasAnyRole(*UserRole.adminAccessValues.toTypedArray())
                    .anyRequest().authenticated()
            }
            .addFilterBefore(bearerTokenFilter, UsernamePasswordAuthenticationFilter::class.java)

        return http.build()
    }
}
