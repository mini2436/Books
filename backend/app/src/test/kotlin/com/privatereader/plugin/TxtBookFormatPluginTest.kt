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

    @Test
    fun `extracts structured content with chapter anchors`() {
        val tempFile = Files.createTempFile("reader-structured", ".txt")
        Files.writeString(
            tempFile,
            """
            Chapter 1

            First paragraph in chapter one.

            > A quoted line.

            Chapter 2

            Second chapter starts here.
            """.trimIndent(),
        )

        val content = plugin.extractStructuredContent(tempFile)

        assertEquals(2, content?.chapters?.size)
        assertEquals("Chapter 1", content?.chapters?.get(0)?.title)
        assertEquals("chapter-0", content?.chapters?.get(0)?.anchor)
        assertEquals("chapter-0-block-1", content?.chapters?.get(0)?.blocks?.first()?.anchor)
        assertEquals("quote", content?.chapters?.get(0)?.blocks?.get(1)?.type?.storageName)
    }
}
