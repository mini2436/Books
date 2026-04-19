package com.privatereader.pluginruntime

import com.fasterxml.jackson.databind.ObjectMapper
import com.privatereader.common.toSqlTimestamp
import com.privatereader.plugin.BookFormatPlugin
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.stereotype.Service
import java.time.Instant

data class RegisteredPluginView(
    val pluginId: String,
    val displayName: String,
    val supportedExtensions: Set<String>,
    val capabilities: Set<String>,
)

@Service
class PluginRegistryService(
    private val plugins: List<BookFormatPlugin>,
    private val jdbcClient: JdbcClient,
    private val objectMapper: ObjectMapper,
) {
    fun all(): List<RegisteredPluginView> = plugins.map {
        RegisteredPluginView(
            pluginId = it.pluginId,
            displayName = it.displayName,
            supportedExtensions = it.supportedExtensions,
            capabilities = it.capabilities.map { capability -> capability.name }.toSet(),
        )
    }.sortedBy { it.pluginId }

    fun findPluginFor(filename: String): BookFormatPlugin? =
        plugins.firstOrNull { plugin -> plugin.supportedExtensions.any { filename.endsWith(".$it", ignoreCase = true) } }

    fun findPluginById(pluginId: String): BookFormatPlugin? =
        plugins.firstOrNull { plugin -> plugin.pluginId == pluginId }

    fun syncRegistry() {
        // Persist the compile-time plugin registry so the admin UI can expose the active scanner
        // capabilities without relying on runtime classpath scanning.
        plugins.forEach { plugin ->
            jdbcClient.sql(
                """
                insert into plugin_registry (plugin_id, display_name, supported_extensions_json, capabilities_json, updated_at)
                values (:pluginId, :displayName, :extensions, :capabilities, :updatedAt)
                on conflict (plugin_id) do update
                set display_name = excluded.display_name,
                    supported_extensions_json = excluded.supported_extensions_json,
                    capabilities_json = excluded.capabilities_json,
                    updated_at = excluded.updated_at
                """.trimIndent(),
            )
                .param("pluginId", plugin.pluginId)
                .param("displayName", plugin.displayName)
                .param("extensions", objectMapper.writeValueAsString(plugin.supportedExtensions))
                .param("capabilities", objectMapper.writeValueAsString(plugin.capabilities.map { it.name }))
                .param("updatedAt", Instant.now().toSqlTimestamp())
                .update()
        }
    }
}
