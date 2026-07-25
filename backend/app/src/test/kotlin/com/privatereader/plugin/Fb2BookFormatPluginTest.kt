package com.privatereader.plugin

import com.privatereader.plugin.fb2.Fb2BookFormatPlugin
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.util.Base64

class Fb2BookFormatPluginTest {
    private val plugin = Fb2BookFormatPlugin()

    @Test
    fun `extracts metadata chapters cover and embedded images`() {
        val file = Files.createTempFile("reader-fictionbook", ".fb2")
        val coverBytes = byteArrayOf(0x01, 0x02, 0x03)
        val illustrationBytes = byteArrayOf(0x04, 0x05, 0x06)
        Files.writeString(
            file,
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0"
                         xmlns:l="http://www.w3.org/1999/xlink">
              <description>
                <title-info>
                  <genre>adventure</genre>
                  <author><first-name>Test</first-name><last-name>Author</last-name></author>
                  <book-title>FB2 Sample</book-title>
                  <annotation><p>A sample description.</p></annotation>
                  <coverpage><image l:href="#cover.jpg"/></coverpage>
                  <lang>zh</lang>
                </title-info>
              </description>
              <body>
                <section id="one">
                  <title><p>第一章</p></title>
                  <p>第一段正文。</p>
                  <subtitle>小标题</subtitle>
                  <cite><p>引用文字。</p></cite>
                  <image l:href="#illustration.png" title="插图"/>
                  <section id="two">
                    <title><p>第二章</p></title>
                    <p>第二段正文。</p>
                  </section>
                </section>
              </body>
              <binary id="cover.jpg" content-type="image/jpeg">${Base64.getEncoder().encodeToString(coverBytes)}</binary>
              <binary id="illustration.png" content-type="image/png">${Base64.getEncoder().encodeToString(illustrationBytes)}</binary>
            </FictionBook>
            """.trimIndent(),
            StandardCharsets.UTF_8,
        )

        val metadata = plugin.extractMetadata(file)
        val content = plugin.extractStructuredContent(file)
        val cover = plugin.extractCover(file)
        val manifest = plugin.buildManifest(file)

        assertEquals("FB2 Sample", metadata.title)
        assertEquals("Test Author", metadata.author)
        assertEquals("A sample description.", metadata.description)
        assertEquals(listOf("第一章", "第二章"), content.chapters.map { it.title })
        assertEquals("paragraph", content.chapters[0].blocks[0].type.storageName)
        assertEquals("heading", content.chapters[0].blocks[1].type.storageName)
        assertEquals("quote", content.chapters[0].blocks[2].type.storageName)
        val imageBlock = content.chapters[0].blocks.first { it.type == StructuredBlockType.IMAGE }
        assertEquals("image/png", imageBlock.meta["mediaType"])
        assertEquals("UNIFIED_V2", content.contentModel)
        assertEquals(listOf("第一章", "第二章"), manifest.toc.map { it.title })
        assertNotNull(cover)
        assertArrayEquals(coverBytes, cover?.bytes)
        assertArrayEquals(
            illustrationBytes,
            plugin.extractResource(file, imageBlock.meta["resourceId"] as String)?.bytes,
        )
        assertTrue(plugin.extractIndexableContent(file)?.text?.contains("第二段正文") == true)
    }
}
