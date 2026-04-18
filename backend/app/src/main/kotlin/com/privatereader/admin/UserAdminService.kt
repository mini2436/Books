package com.privatereader.admin

import com.privatereader.auth.AuthRepository
import com.privatereader.books.CreateUserRequest
import com.privatereader.books.UpdateUserRequest
import com.privatereader.books.UserView
import com.privatereader.common.toSqlTimestamp
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.stereotype.Service
import java.time.Instant

@Service
class UserAdminService(
    private val authRepository: AuthRepository,
    private val jdbcClient: JdbcClient,
    private val passwordEncoder: PasswordEncoder,
) {
    fun createUser(request: CreateUserRequest): UserView {
        val normalizedRole = normalizeRole(request.role)
        val userId = authRepository.insertUser(
            username = request.username,
            passwordHash = passwordEncoder.encode(request.password),
            role = normalizedRole,
            enabled = true,
        )
        return UserView(id = userId, username = request.username, role = normalizedRole, enabled = true)
    }

    fun updateUser(userId: Long, request: UpdateUserRequest): UserView {
        val existing = authRepository.findUserById(userId) ?: throw IllegalArgumentException("User not found")
        val newRole = request.role?.let(::normalizeRole) ?: existing.role
        val newEnabled = request.enabled ?: existing.enabled
        jdbcClient.sql(
            """
            update users set role = :role, enabled = :enabled, updated_at = :updatedAt
            where id = :userId
            """.trimIndent(),
        )
            .param("role", newRole)
            .param("enabled", newEnabled)
            .param("updatedAt", Instant.now().toSqlTimestamp())
            .param("userId", userId)
            .update()
        return UserView(id = existing.id, username = existing.username, role = newRole, enabled = newEnabled)
    }

    fun listUsers(): List<UserView> =
        jdbcClient.sql("select id, username, role, enabled from users order by id asc")
            .query { rs, _ ->
                UserView(
                    id = rs.getLong("id"),
                    username = rs.getString("username"),
                    role = rs.getString("role"),
                    enabled = rs.getBoolean("enabled"),
                )
            }
            .list()

    private fun normalizeRole(role: String): String {
        val normalized = role.trim().uppercase()
        require(normalized in setOf("SUPER_ADMIN", "LIBRARIAN", "READER")) { "Unsupported role" }
        return normalized
    }
}
