package com.privatereader.auth

enum class UserRole(val value: String) {
    SUPER_ADMIN(RoleNames.SUPER_ADMIN),
    LIBRARIAN(RoleNames.LIBRARIAN),
    READER(RoleNames.READER),
    ;

    companion object {
        val allValues: Set<String> = entries.mapTo(linkedSetOf()) { it.value }
        val adminAccessValues: List<String> = listOf(SUPER_ADMIN.value, LIBRARIAN.value)

        fun normalize(raw: String): String {
            val normalized = raw.trim().uppercase()
            require(normalized in allValues) { "Unsupported role" }
            return normalized
        }

        fun hasGlobalLibraryAccess(role: String): Boolean = role in adminAccessValues
    }
}

object RoleNames {
    const val SUPER_ADMIN = "SUPER_ADMIN"
    const val LIBRARIAN = "LIBRARIAN"
    const val READER = "READER"
}

object RoleAuthorities {
    const val PREFIX = "ROLE_"
    const val SUPER_ADMIN = PREFIX + RoleNames.SUPER_ADMIN
    const val LIBRARIAN = PREFIX + RoleNames.LIBRARIAN
    const val READER = PREFIX + RoleNames.READER

    fun fromRole(role: String): String = PREFIX + role
}

object RoleExpressions {
    const val SUPER_ADMIN_ONLY = "hasAuthority('" + RoleAuthorities.SUPER_ADMIN + "')"
    const val ADMIN_ACCESS =
        "hasAnyAuthority('" + RoleAuthorities.SUPER_ADMIN + "','" + RoleAuthorities.LIBRARIAN + "')"
}
