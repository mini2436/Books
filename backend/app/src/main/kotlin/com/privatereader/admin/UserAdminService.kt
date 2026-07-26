package com.privatereader.admin

import com.privatereader.auth.AuthRepository
import com.privatereader.auth.UserRole
import com.privatereader.books.CreateUserRequest
import com.privatereader.books.UpdateUserRequest
import com.privatereader.books.UserView
import com.privatereader.common.toSqlTimestamp
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
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

    @Transactional
    fun updateUser(actorId: Long, userId: Long, request: UpdateUserRequest): UserView {
        val existing = authRepository.findUserById(userId) ?: throw IllegalArgumentException("User not found")
        if (actorId == userId && request.role != null) {
            val requestedRole = normalizeRole(request.role)
            require(requestedRole == existing.role) { "Administrators cannot change their own role" }
        }
        val newRole = request.role?.let(::normalizeRole) ?: existing.role
        val newEnabled = request.enabled ?: existing.enabled
        if (existing.role == UserRole.SUPER_ADMIN.value && existing.enabled && !newEnabled) {
            require(actorId == userId) { "Administrators can only disable their own account" }
            val enabledAdministratorIds = lockEnabledAdministratorIds()
            require(enabledAdministratorIds.size > 1) { "The last enabled administrator cannot be disabled" }
        }
        // 更新指定用户的角色和启用状态，用于超级管理员维护账号权限。
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

    fun resetUserPassword(userId: Long, request: ResetUserPasswordRequest): UserView {
        val existing = authRepository.findUserById(userId) ?: throw IllegalArgumentException("User not found")
        require(existing.role != UserRole.SUPER_ADMIN.value) {
            "Super administrator passwords cannot be reset from user management"
        }
        authRepository.updatePassword(userId, passwordEncoder.encode(request.newPassword))
        return UserView(
            id = existing.id,
            username = existing.username,
            role = existing.role,
            enabled = existing.enabled,
        )
    }

    fun listUsers(): List<UserView> =
        // 查询全部用户的基础管理信息，并按创建顺序展示在后台用户列表。
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
        return UserRole.normalize(role)
    }

    private fun lockEnabledAdministratorIds(): List<Long> =
        // 锁定全部启用中的超级管理员，避免并发停用造成系统瞬间失去管理员。
        jdbcClient.sql(
            """
            select id from users
            where role = :role and enabled = true
            order by id
            for update
            """.trimIndent(),
        )
            .param("role", UserRole.SUPER_ADMIN.value)
            .query(Long::class.java)
            .list()
}
