package com.privatereader.admin

import com.privatereader.auth.AuthRepository
import com.privatereader.auth.UserRole
import com.privatereader.books.UpdateUserRequest
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.jdbc.datasource.DriverManagerDataSource
import org.springframework.security.crypto.factory.PasswordEncoderFactories

class UserAdminServiceEnabledTest {
    private lateinit var jdbcClient: JdbcClient
    private lateinit var service: UserAdminService

    @BeforeEach
    fun setUp() {
        val dataSource = DriverManagerDataSource(
            "jdbc:h2:mem:user-admin-${System.nanoTime()};MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
            "sa",
            "",
        )
        jdbcClient = JdbcClient.create(dataSource)
        jdbcClient.sql(
            """
            create table users (
                id bigint primary key,
                username varchar(255) not null,
                password_hash varchar(255) not null,
                role varchar(32) not null,
                enabled boolean not null,
                display_name varchar(255),
                avatar_updated_at timestamp,
                updated_at timestamp not null
            )
            """.trimIndent(),
        ).update()
        service = UserAdminService(
            AuthRepository(jdbcClient),
            jdbcClient,
            PasswordEncoderFactories.createDelegatingPasswordEncoder(),
        )
    }

    @Test
    fun `last enabled administrator cannot disable itself`() {
        insertAdministrator(1)

        assertThrows(IllegalArgumentException::class.java) {
            service.updateUser(1, 1, UpdateUserRequest(enabled = false))
        }
    }

    @Test
    fun `administrator cannot disable another administrator`() {
        insertAdministrator(1)
        insertAdministrator(2)

        assertThrows(IllegalArgumentException::class.java) {
            service.updateUser(1, 2, UpdateUserRequest(enabled = false))
        }
    }

    @Test
    fun `administrator can disable itself when another enabled administrator remains`() {
        insertAdministrator(1)
        insertAdministrator(2)

        val updated = service.updateUser(1, 1, UpdateUserRequest(enabled = false))

        assertFalse(updated.enabled)
    }

    private fun insertAdministrator(id: Long) {
        jdbcClient.sql(
            """
            insert into users (id, username, password_hash, role, enabled, updated_at)
            values (:id, :username, 'unused', :role, true, current_timestamp)
            """.trimIndent(),
        )
            .param("id", id)
            .param("username", "admin$id")
            .param("role", UserRole.SUPER_ADMIN.value)
            .update()
    }
}
