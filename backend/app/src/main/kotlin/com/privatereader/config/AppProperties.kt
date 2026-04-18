package com.privatereader.config

import org.springframework.boot.context.properties.ConfigurationProperties

@ConfigurationProperties(prefix = "app")
data class AppProperties(
    val storageRoot: String = "storage",
    val scanRoot: String = "storage/nas",
    val bootstrapAdminUsername: String = "admin",
    val bootstrapAdminPassword: String = "admin12345",
    val accessTokenTtlMinutes: Long = 120,
    val refreshTokenTtlDays: Long = 30,
)

