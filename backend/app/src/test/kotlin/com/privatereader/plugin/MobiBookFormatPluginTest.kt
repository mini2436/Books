package com.privatereader.plugin

import com.privatereader.plugin.mobi.MobiBookFormatPlugin
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.ByteArrayOutputStream
import java.nio.charset.StandardCharsets
import java.nio.file.Files

class MobiBookFormatPluginTest {
    private val plugin = MobiBookFormatPlugin()

    @Test
    fun `extracts palmdoc text exth metadata chapters and cover`() {
        val html = """
            <html><body>
              <h1>Intro</h1><p>First paragraph.</p>
              <p><img recindex="1" alt="Cover art" width="320"/></p>
              <mbp:pagebreak/>
              <h1>Next</h1><blockquote>Quoted text.</blockquote>
            </body></html>
        """.trimIndent()
        val imageBytes = byteArrayOf(
            0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
            0x01, 0x02, 0x03,
        )
        val file = Files.createTempFile("reader-sample", ".mobi")
        Files.write(file, buildMobi(html, imageBytes))

        val metadata = plugin.extractMetadata(file)
        val content = plugin.extractStructuredContent(file)
        val manifest = plugin.buildManifest(file)
        val cover = plugin.extractCover(file)

        assertEquals("MOBI Sample", metadata.title)
        assertEquals("Test Author", metadata.author)
        assertEquals("A sample MOBI.", metadata.description)
        assertEquals("en", metadata.language)
        assertEquals(listOf("Intro", "Next"), content.chapters.map { it.title })
        assertEquals("paragraph", content.chapters[0].blocks[0].type.storageName)
        val imageBlock = content.chapters[0].blocks.first { it.type == StructuredBlockType.IMAGE }
        assertEquals("image/png", imageBlock.meta["mediaType"])
        assertEquals(320, imageBlock.meta["width"])
        assertEquals("quote", content.chapters[1].blocks.single().type.storageName)
        assertEquals(listOf("Intro", "Next"), manifest.toc.map { it.title })
        assertEquals("UNIFIED_V2", content.contentModel)
        assertNotNull(cover)
        assertArrayEquals(imageBytes, cover?.bytes)
        assertArrayEquals(imageBytes, plugin.extractResource(file, imageBlock.meta["resourceId"] as String)?.bytes)
        assertTrue(plugin.extractIndexableContent(file)?.text?.contains("Quoted text") == true)
    }

    @Test
    fun `rejects drm protected mobi`() {
        val file = Files.createTempFile("reader-drm", ".mobi")
        Files.write(file, buildMobi("<p>Protected</p>", byteArrayOf(), encryption = 1))

        val exception = assertThrows(IllegalArgumentException::class.java) { plugin.extractMetadata(file) }

        assertTrue(exception.message.orEmpty().contains("DRM"))
    }

    @Test
    fun `decompresses palmdoc back references`() {
        val file = Files.createTempFile("reader-compressed", ".mobi")
        val compressed = byteArrayOf('a'.code.toByte(), 'b'.code.toByte(), 'c'.code.toByte(), 0x80.toByte(), 0x18)
        Files.write(file, buildMobi("abcabc", byteArrayOf(), textRecord = compressed))

        val content = plugin.extractStructuredContent(file)

        assertEquals("abcabc", content.chapters.single().blocks.single().text)
    }

    @Test
    fun `removes mobi trailing data before palmdoc decompression`() {
        val file = Files.createTempFile("reader-trailing-data", ".mobi")
        val html = "<p>Readable text</p>"
        val textWithTrailingEntry = html.toByteArray(StandardCharsets.UTF_8) + byteArrayOf(0x55, 0x82.toByte())
        Files.write(file, buildMobi(html, byteArrayOf(), textRecord = textWithTrailingEntry, extraDataFlags = 2))

        val content = plugin.extractStructuredContent(file)

        assertEquals("Readable text", content.chapters.single().blocks.single().text)
    }

    private fun buildMobi(
        html: String,
        image: ByteArray,
        encryption: Int = 0,
        textRecord: ByteArray = html.toByteArray(StandardCharsets.UTF_8),
        extraDataFlags: Int = 0,
    ): ByteArray {
        val textLength = html.toByteArray(StandardCharsets.UTF_8).size
        val exth = buildExth(
            503 to "MOBI Sample".toByteArray(StandardCharsets.UTF_8),
            100 to "Test Author".toByteArray(StandardCharsets.UTF_8),
            103 to "<p>A sample MOBI.</p>".toByteArray(StandardCharsets.UTF_8),
            524 to "en".toByteArray(StandardCharsets.UTF_8),
            201 to byteArrayOf(0, 0, 0, 0),
        )
        val mobiHeaderLength = 232
        val exthOffset = 16 + mobiHeaderLength
        val fullName = "Fallback title".toByteArray(StandardCharsets.UTF_8)
        val fullNameOffset = exthOffset + exth.size
        val record0 = ByteArray(fullNameOffset + fullName.size)
        record0.putU16(0, 2)
        record0.putU32(4, textLength)
        record0.putU16(8, 1)
        record0.putU16(10, 4096)
        record0.putU16(12, encryption)
        record0.putAscii(16, "MOBI")
        record0.putU32(20, mobiHeaderLength)
        record0.putU32(28, 65001)
        record0.putU32(84, fullNameOffset)
        record0.putU32(88, fullName.size)
        record0.putU32(108, 2)
        record0.putU32(128, 0x40)
        record0.putU16(242, extraDataFlags)
        exth.copyInto(record0, exthOffset)
        fullName.copyInto(record0, fullNameOffset)

        val records = listOf(record0, textRecord, image)
        val palmHeaderLength = 78 + records.size * 8
        val file = ByteArrayOutputStream()
        val palmHeader = ByteArray(palmHeaderLength)
        palmHeader.putAscii(0, "MOBI test")
        palmHeader.putAscii(60, "BOOK")
        palmHeader.putAscii(64, "MOBI")
        palmHeader.putU16(76, records.size)
        var recordOffset = palmHeaderLength
        records.forEachIndexed { index, record ->
            palmHeader.putU32(78 + index * 8, recordOffset)
            recordOffset += record.size
        }
        file.write(palmHeader)
        records.forEach(file::write)
        return file.toByteArray()
    }

    private fun buildExth(vararg values: Pair<Int, ByteArray>): ByteArray {
        val totalLength = 12 + values.sumOf { 8 + it.second.size }
        val result = ByteArray(totalLength)
        result.putAscii(0, "EXTH")
        result.putU32(4, totalLength)
        result.putU32(8, values.size)
        var cursor = 12
        values.forEach { (type, payload) ->
            result.putU32(cursor, type)
            result.putU32(cursor + 4, payload.size + 8)
            payload.copyInto(result, cursor + 8)
            cursor += payload.size + 8
        }
        return result
    }

    private fun ByteArray.putAscii(offset: Int, value: String) {
        value.toByteArray(StandardCharsets.US_ASCII).copyInto(this, offset)
    }

    private fun ByteArray.putU16(offset: Int, value: Int) {
        this[offset] = (value ushr 8).toByte()
        this[offset + 1] = value.toByte()
    }

    private fun ByteArray.putU32(offset: Int, value: Int) {
        this[offset] = (value ushr 24).toByte()
        this[offset + 1] = (value ushr 16).toByte()
        this[offset + 2] = (value ushr 8).toByte()
        this[offset + 3] = value.toByte()
    }
}
