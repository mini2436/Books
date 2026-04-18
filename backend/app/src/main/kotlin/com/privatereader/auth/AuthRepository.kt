package com.privatereader.auth

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
        jdbcClient.sql(
            """
            select id, username, password_hash, role, enabled
            from users
            where username = :username
            """.trimIndent(),
        )
            .param("username", username)
            .query { rs, _ -> rs.toUserRecord() }
            .optional()
            .orElse(null)

    fun findUserById(id: Long): UserRecord? =
        jdbcClient.sql(
            """
            select id, username, password_hash, role, enabled
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
            .param("expiresAt", expiresAt)
            .param("refreshExpiresAt", refreshExpiresAt)
            .param("createdAt", Instant.now())
            .update()
    }

    fun findActiveTokenByAccessHash(accessTokenHash: String): TokenRecord? =
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
        jdbcClient.sql("update auth_tokens set revoked = true where id = :id")
            .param("id", id)
            .update()
    }

    fun countUsers(): Long =
        jdbcClient.sql("select count(*) from users")
            .query(Long::class.java)
            .single()

    fun insertUser(
        username: String,
        passwordHash: String,
        role: String,
        enabled: Boolean = true,
    ): Long =
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
            .param("now", Instant.now())
            .query(Long::class.java)
            .single()

    private fun ResultSet.toUserRecord(): UserRecord = UserRecord(
        id = getLong("id"),
        username = getString("username"),
        passwordHash = getString("password_hash"),
        role = getString("role"),
        enabled = getBoolean("enabled"),
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

