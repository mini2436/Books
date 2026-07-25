package com.privatereader.plugin

import com.privatereader.plugin.cbz.CbzBookFormatPlugin
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class CbzBookFormatPluginTest {
    private val plugin = CbzBookFormatPlugin()

    @Test
    fun `extracts comic metadata and naturally ordered pages`() {
        val file = Files.createTempFile("reader-comic", ".cbz")
        val firstPage = byteArrayOf(0x01, 0x02, 0x03)
        ZipOutputStream(Files.newOutputStream(file)).use { zip ->
            writeText(
                zip,
                "ComicInfo.xml",
                """
                <ComicInfo>
                  <Title>Example Comic</Title>
                  <Writer>Example Writer</Writer>
                  <Summary>A test comic.</Summary>
                  <Genre>Adventure, Family</Genre>
                  <LanguageISO>zh-Hans</LanguageISO>
                  <Pages><Page Image="1" Type="FrontCover"/></Pages>
                </ComicInfo>
                """.trimIndent(),
            )
            writeBytes(zip, "pages/10.png", byteArrayOf(0x10))
            writeBytes(zip, "pages/2.png", byteArrayOf(0x02))
            writeBytes(zip, "pages/1.png", firstPage)
            writeBytes(zip, "__MACOSX/._1.png", byteArrayOf(0x00))
        }

        val metadata = plugin.extractMetadata(file)
        val manifest = plugin.buildManifest(file)
        val content = plugin.extractStructuredContent(file)
        val cover = plugin.extractCover(file)

        assertEquals("Example Comic", metadata.title)
        assertEquals("Example Writer", metadata.author)
        assertEquals(listOf("Page 1", "Page 2", "Page 3"), manifest.toc.map { it.title })
        assertEquals(3, content.chapters.size)
        assertEquals("pages/1.png", content.chapters[0].blocks.single().meta["src"])
        assertEquals("pages/2.png", content.chapters[1].blocks.single().meta["src"])
        assertEquals("pages/10.png", content.chapters[2].blocks.single().meta["src"])
        assertEquals("UNIFIED_V2", content.contentModel)
        assertNotNull(cover)
        assertArrayEquals(byteArrayOf(0x02), cover?.bytes)

        val resourceId = content.chapters.first().blocks.single().meta["resourceId"] as String
        assertArrayEquals(firstPage, plugin.extractResource(file, resourceId)?.bytes)
        assertTrue(plugin.canHandle(file))
    }

    private fun writeText(zip: ZipOutputStream, name: String, content: String) =
        writeBytes(zip, name, content.toByteArray(StandardCharsets.UTF_8))

    private fun writeBytes(zip: ZipOutputStream, name: String, content: ByteArray) {
        zip.putNextEntry(ZipEntry(name))
        zip.write(content)
        zip.closeEntry()
    }
}
