package com.privatereader.plugin

import com.fasterxml.jackson.databind.ObjectMapper
import com.privatereader.plugin.cbz.CbzBookFormatPlugin
import com.privatereader.plugin.fb2.Fb2BookFormatPlugin
import com.privatereader.plugin.mobi.MobiBookFormatPlugin
import com.privatereader.pluginruntime.PluginRegistryService
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource
import org.mockito.kotlin.mock
import org.springframework.jdbc.core.simple.JdbcClient

class PluginRegistryFormatSelectionTest {
    private val registry = PluginRegistryService(
        plugins = listOf(CbzBookFormatPlugin(), Fb2BookFormatPlugin(), MobiBookFormatPlugin()),
        jdbcClient = mock<JdbcClient>(),
        objectMapper = ObjectMapper(),
    )

    @ParameterizedTest
    @CsvSource(
        "comic.CBZ, plugin-cbz",
        "novel.fb2, plugin-fb2",
        "kindle-book.MoBi, plugin-mobi",
    )
    fun `selects new plugins case insensitively`(filename: String, expectedPluginId: String) {
        assertEquals(expectedPluginId, registry.findPluginFor(filename)?.pluginId)
    }
}
