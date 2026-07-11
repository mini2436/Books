package com.privatereader.auth

import com.privatereader.common.toSqlTimestamp
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Repository
import java.sql.ResultSet
import java.time.Instant

data class UserRecord(
    val id: Long,
    val username: String,
    val passwordHash: String,
    val role: String,
    val enabled: Boolean,
    val displayName: String? = null,
    val avatarUpdatedAt: Instant? = null,
)

data class UserAvatarRecord(
    val bytes: ByteArray,
    val contentType: String,
    val updatedAt: Instant,
)

data class TokenRecord(
    val id: Long,
    val userId: Long,
    val accessTokenHash: String,
    val refreshTokenHash: String,
    val expiresAt: Instant,
    val refreshExpiresAt: Instant,
    val revoked: Boolean,
)

@Repository
class AuthRepository(
    private val jdbcClient: JdbcClient,
) {
    fun findUserByUsername(username: String): UserRecord? =
        // 查询指定用户名的用户记录，用于登录时校验密码与账号状态。
        jdbcClient.sql(
            """
            select id, username, password_hash, role, enabled, display_name, avatar_updated_at
            from users
            where username = :username
            """.trimIndent(),
        )
            .param("username", username)
            .query { rs, _ -> rs.toUserRecord() }
            .optional()
            .orElse(null)

    fun findUserById(id: Long): UserRecord? =
        // 按用户 ID 查询用户记录，用于令牌刷新、权限判断和后台管理回显。
        jdbcClient.sql(
            """
            select id, username, password_hash, role, enabled, display_name, avatar_updated_at
            from users
            where id = :id
            """.trimIndent(),
        )
            .param("id", id)
            .query { rs, _ -> rs.toUserRecord() }
            .optional()
            .orElse(null)

    fun createToken(
        userId: Long,
        accessTokenHash: String,
        refreshTokenHash: String,
        expiresAt: Instant,
        refreshExpiresAt: Instant,
    ) {
        // 新增访问令牌与刷新令牌的哈希记录，保存过期时间供后续认证校验。
        jdbcClient.sql(
            """
            insert into auth_tokens (
                user_id,
                access_token_hash,
                refresh_token_hash,
                expires_at,
                refresh_expires_at,
                revoked,
                created_at
            ) values (
                :userId,
                :accessTokenHash,
                :refreshTokenHash,
                :expiresAt,
                :refreshExpiresAt,
                false,
                :createdAt
            )
            """.trimIndent(),
        )
            .param("userId", userId)
            .param("accessTokenHash", accessTokenHash)
            .param("refreshTokenHash", refreshTokenHash)
            .param("expiresAt", expiresAt.toSqlTimestamp())
            .param("refreshExpiresAt", refreshExpiresAt.toSqlTimestamp())
            .param("createdAt", Instant.now().toSqlTimestamp())
            .update()
    }

    fun findActiveTokenByAccessHash(accessTokenHash: String): TokenRecord? =
        // 根据访问令牌哈希查询未撤销的令牌记录，用于接口请求认证。
        jdbcClient.sql(
            """
            select id, user_id, access_token_hash, refresh_token_hash, expires_at, refresh_expires_at, revoked
            from auth_tokens
            where access_token_hash = :accessTokenHash
            and revoked = false
            """.trimIndent(),
        )
            .param("accessTokenHash", accessTokenHash)
            .query { rs, _ -> rs.toTokenRecord() }
            .optional()
            .orElse(null)

    fun findActiveTokenByRefreshHash(refreshTokenHash: String): TokenRecord? =
        // 根据刷新令牌哈希查询未撤销的令牌记录，用于续签登录态。
        jdbcClient.sql(
            """
            select id, user_id, access_token_hash, refresh_token_hash, expires_at, refresh_expires_at, revoked
            from auth_tokens
            where refresh_token_hash = :refreshTokenHash
            and revoked = false
            """.trimIndent(),
        )
            .param("refreshTokenHash", refreshTokenHash)
            .query { rs, _ -> rs.toTokenRecord() }
            .optional()
            .orElse(null)

    fun revokeToken(id: Long) {
        // 将指定令牌标记为已撤销，避免登出或过期后的令牌继续使用。
        jdbcClient.sql("update auth_tokens set revoked = true where id = :id")
            .param("id", id)
            .update()
    }

    fun countUsers(): Long =
        // 统计用户总数，用于判断是否需要初始化第一个管理员账号。
        jdbcClient.sql("select count(*) from users")
            .query(Long::class.java)
            .single()

    fun insertUser(
        username: String,
        passwordHash: String,
        role: String,
        enabled: Boolean = true,
    ): Long =
        // 创建用户并返回新用户 ID，供启动初始化和后台用户管理使用。
        jdbcClient.sql(
            """
            insert into users (username, password_hash, role, enabled, created_at, updated_at)
            values (:username, :passwordHash, :role, :enabled, :now, :now)
            returning id
            """.trimIndent(),
        )
            .param("username", username)
            .param("passwordHash", passwordHash)
            .param("role", role)
            .param("enabled", enabled)
            .param("now", Instant.now().toSqlTimestamp())
            .query(Long::class.java)
            .single()

    fun updateDisplayName(userId: Long, displayName: String?): UserRecord {
        jdbcClient.sql(
            """
            update users
            set display_name = :displayName, updated_at = :updatedAt
            where id = :userId
            """.trimIndent(),
        )
            .param("displayName", displayName)
            .param("updatedAt", Instant.now().toSqlTimestamp())
            .param("userId", userId)
            .update()
        return requireNotNull(findUserById(userId)) { "User not found" }
    }

    fun updateAvatar(userId: Long, bytes: ByteArray, contentType: String): UserRecord {
        val now = Instant.now()
        jdbcClient.sql(
            """
            update users
            set avatar_data = :bytes,
                avatar_content_type = :contentType,
                avatar_updated_at = :updatedAt,
                updated_at = :updatedAt
            where id = :userId
            """.trimIndent(),
        )
            .param("bytes", bytes)
            .param("contentType", contentType)
            .param("updatedAt", now.toSqlTimestamp())
            .param("userId", userId)
            .update()
        return requireNotNull(findUserById(userId)) { "User not found" }
    }

    fun findAvatar(userId: Long): UserAvatarRecord? =
        jdbcClient.sql(
            """
            select avatar_data, avatar_content_type, avatar_updated_at
            from users
            where id = :userId and avatar_data is not null
            """.trimIndent(),
        )
            .param("userId", userId)
            .query { rs, _ ->
                UserAvatarRecord(
                    bytes = rs.getBytes("avatar_data"),
                    contentType = rs.getString("avatar_content_type"),
                    updatedAt = rs.getTimestamp("avatar_updated_at").toInstant(),
                )
            }
            .optional()
            .orElse(null)

    private fun ResultSet.toUserRecord(): UserRecord = UserRecord(
        id = getLong("id"),
        username = getString("username"),
        passwordHash = getString("password_hash"),
        role = getString("role"),
        enabled = getBoolean("enabled"),
        displayName = getString("display_name"),
        avatarUpdatedAt = getTimestamp("avatar_updated_at")?.toInstant(),
    )

    private fun ResultSet.toTokenRecord(): TokenRecord = TokenRecord(
        id = getLong("id"),
        userId = getLong("user_id"),
        accessTokenHash = getString("access_token_hash"),
        refreshTokenHash = getString("refresh_token_hash"),
        expiresAt = getTimestamp("expires_at").toInstant(),
        refreshExpiresAt = getTimestamp("refresh_expires_at").toInstant(),
        revoked = getBoolean("revoked"),
    )
}

fun UserRecord.toAuthUserView(): AuthUserView = AuthUserView(
    id = id,
    username = username,
    displayName = displayName,
    role = role,
    hasAvatar = avatarUpdatedAt != null,
    avatarVersion = avatarUpdatedAt?.toEpochMilli()?.toString(),
)
