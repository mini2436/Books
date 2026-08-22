package com.privatereader.admin

import com.privatereader.auth.AuthRepository
import com.privatereader.auth.UserRole
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.jdbc.datasource.DriverManagerDataSource
import org.springframework.security.crypto.factory.PasswordEncoderFactories

class UserAdminServiceDeleteTest {
    private lateinit var jdbcClient: JdbcClient
    private lateinit var service: UserAdminService
    private val passwordEncoder = PasswordEncoderFactories.createDelegatingPasswordEncoder()

    @BeforeEach
    fun setUp() {
        val dataSource = DriverManagerDataSource(
            "jdbc:h2:mem:user-admin-delete-${System.nanoTime()};MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
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
            );
            create table user_book_access (
                user_id bigint not null references users(id) on delete cascade,
                book_id bigint not null,
                granted_by bigint not null references users(id),
                granted_at timestamp not null,
                primary key (user_id, book_id)
            )
            """.trimIndent(),
        ).update()
        insertUser(1, "actor", UserRole.SUPER_ADMIN, "actor-password")
        insertUser(2, "target", UserRole.SUPER_ADMIN, "target-password")
        insertUser(3, "reader", UserRole.READER, "reader-password")
        service = UserAdminService(AuthRepository(jdbcClient), jdbcClient, passwordEncoder)
    }

    @Test
    fun `correct target password deletes administrator and preserves grants`() {
        jdbcClient.sql(
            """
            insert into user_book_access (user_id, book_id, granted_by, granted_at)
            values (3, 10, 2, current_timestamp)
            """.trimIndent(),
        ).update()

        service.deleteAdministrator(1, 2, DeleteAdministratorRequest("target-password"))

        assertEquals(
            0L,
            jdbcClient.sql("select count(*) from users where id = 2").query(Long::class.java).single(),
        )
        assertEquals(
            1L,
            jdbcClient.sql("select granted_by from user_book_access where user_id = 3 and book_id = 10")
                .query(Long::class.java)
                .single(),
        )
    }

    @Test
    fun `wrong target password does not delete administrator`() {
        assertThrows(IllegalArgumentException::class.java) {
            service.deleteAdministrator(1, 2, DeleteAdministratorRequest("wrong-password"))
        }

        assertEquals(
            1L,
            jdbcClient.sql("select count(*) from users where id = 2").query(Long::class.java).single(),
        )
    }

    @Test
    fun `administrator cannot delete itself`() {
        assertThrows(IllegalArgumentException::class.java) {
            service.deleteAdministrator(1, 1, DeleteAdministratorRequest("actor-password"))
        }
    }

    private fun insertUser(id: Long, username: String, role: UserRole, password: String) {
        jdbcClient.sql(
            """
            insert into users (id, username, password_hash, role, enabled, updated_at)
            values (:id, :username, :passwordHash, :role, true, current_timestamp)
            """.trimIndent(),
        )
            .param("id", id)
            .param("username", username)
            .param("passwordHash", passwordEncoder.encode(password))
            .param("role", role.value)
            .update()
    }
}
