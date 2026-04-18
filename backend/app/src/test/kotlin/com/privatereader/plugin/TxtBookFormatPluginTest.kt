package com.privatereader.plugin

import com.privatereader.plugin.txt.TxtBookFormatPlugin
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.nio.file.Files

class TxtBookFormatPluginTest {
    private val plugin = TxtBookFormatPlugin()

    @Test
    fun `extracts metadata and indexable text`() {
        val tempFile = Files.createTempFile("reader-test", ".txt")
        Files.writeString(tempFile, "hello private reader")

        val metadata = plugin.extractMetadata(tempFile)
        val content = plugin.extractIndexableContent(tempFile)

        assertTrue(plugin.canHandle(tempFile))
        assertEquals("hello private reader", content?.text)
        assertTrue(metadata.title.contains("reader-test"))
    }
}

