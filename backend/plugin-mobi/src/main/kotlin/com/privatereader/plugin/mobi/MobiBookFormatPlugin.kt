package com.privatereader.plugin.mobi

import com.privatereader.plugin.BookFormatPlugin
import com.privatereader.plugin.BookMetadata
import com.privatereader.plugin.BookResource
import com.privatereader.plugin.CoverExtractionResult
import com.privatereader.plugin.IndexableContent
import com.privatereader.plugin.ManifestTocItem
import com.privatereader.plugin.PluginCapability
import com.privatereader.plugin.ReadingManifest
import com.privatereader.plugin.StructuredBlockType
import com.privatereader.plugin.StructuredBookBlock
import com.privatereader.plugin.StructuredBookChapter
import com.privatereader.plugin.StructuredBookContent
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.jsoup.nodes.Node
import org.jsoup.nodes.TextNode
import org.springframework.stereotype.Component
import java.io.ByteArrayOutputStream
import java.nio.charset.Charset
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.util.Base64

@Component
class MobiBookFormatPlugin : BookFormatPlugin {
    override val pluginId: String = "plugin-mobi"
    override val displayName: String = "MOBI Plugin"
    override val supportedExtensions: Set<String> = setOf("mobi")
    override val capabilities: Set<PluginCapability> = setOf(
        PluginCapability.READ_ONLINE,
        PluginCapability.EXTRACT_TOC,
        PluginCapability.EXTRACT_COVER,
        PluginCapability.FULL_TEXT_INDEX,
        PluginCapability.SUPPORTS_ANNOTATIONS,
    )

    override fun canHandle(file: Path): Boolean = file.fileName.toString().endsWith(".mobi", ignoreCase = true)

    override fun extractMetadata(file: Path): BookMetadata = parse(file).metadata

    override fun extractCover(file: Path): CoverExtractionResult? {
        val mobi = parse(file)
        val image = mobi.coverRecordIndex?.let(mobi.images::get) ?: mobi.images.values.firstOrNull() ?: return null
        return CoverExtractionResult(image.mimeType, image.bytes)
    }

    override fun extractResource(file: Path, resourceId: String): BookResource? {
        val recordIndex = decodeResourceId(resourceId) ?: return null
        val image = parse(file).images[recordIndex] ?: return null
        return BookResource(image.mimeType, image.bytes)
    }

    override fun buildManifest(file: Path): ReadingManifest {
        val content = parse(file).content
        return ReadingManifest(
            format = "mobi",
            toc = content.chapters.map { ManifestTocItem(it.title, it.anchor) },
            primaryLocation = content.chapters.firstOrNull()?.anchor ?: "chapter-0",
        )
    }

    override fun extractIndexableContent(file: Path): IndexableContent? {
        val mobi = parse(file)
        val text = mobi.content.chapters.asSequence()
            .flatMap { chapter -> sequenceOf(chapter.title) + chapter.blocks.asSequence().map { it.plainText } }
            .joinToString(" ")
            .normalizeWhitespace()
            .take(MAX_INDEX_LENGTH)
        return text.takeIf(String::isNotBlank)?.let(::IndexableContent)
    }

    override fun extractStructuredContent(file: Path): StructuredBookContent = parse(file).content

    private fun parse(file: Path): ParsedMobi {
        val bytes = Files.readAllBytes(file)
        val records = readPalmRecords(bytes)
        val header = records.firstOrNull() ?: throw invalid("missing PalmDOC header record")
        if (header.size < MOBI_START + 8 || header.ascii(MOBI_START, 4) != "MOBI") {
            throw invalid("record 0 does not contain a MOBI header")
        }

        val compression = header.u16(0)
        if (compression !in setOf(COMPRESSION_NONE, COMPRESSION_PALMDOC, COMPRESSION_HUFF_CDIC)) {
            throw invalid("unsupported PalmDOC compression $compression")
        }
        if (compression == COMPRESSION_HUFF_CDIC) {
            throw UnsupportedOperationException("HUFF/CDIC-compressed MOBI files are not supported")
        }
        val encryption = header.u16(12)
        if (encryption != 0) {
            throw IllegalArgumentException("DRM-protected MOBI files are not supported")
        }

        val textLength = header.u32(4).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        val textRecordCount = header.u16(8)
        require(textRecordCount in 1 until records.size) { "MOBI text record table is invalid" }
        val mobiHeaderLength = header.u32(MOBI_START + 4).toIntChecked("MOBI header length")
        require(mobiHeaderLength >= MIN_MOBI_HEADER_LENGTH && MOBI_START + mobiHeaderLength <= header.size) {
            "MOBI header length is invalid"
        }
        val charset = mobiCharset(header.u32(MOBI_START + 12))
        val extraDataFlags = if (mobiHeaderLength >= EXTRA_DATA_FLAGS_OFFSET + 2) {
            header.u16(MOBI_START + EXTRA_DATA_FLAGS_OFFSET)
        } else {
            0
        }
        val exth = readExth(header, mobiHeaderLength)
        val firstImageIndex = header.u32OrNull(MOBI_START + FIRST_IMAGE_INDEX_OFFSET)
            ?.takeUnless { it == UINT32_MAX }
            ?.toIntChecked("first image record")
        val images = extractImages(records, firstImageIndex)
        val coverOffset = exth.firstInt(EXTH_COVER_OFFSET)
        val coverRecordIndex = if (firstImageIndex != null && coverOffset != null) {
            (firstImageIndex + coverOffset).takeIf(images::containsKey)
        } else {
            null
        }

        val initialTextCapacity = textLength.coerceIn(1_024, 1_048_576)
        val rawText = ByteArrayOutputStream(initialTextCapacity).use { output ->
            for (recordIndex in 1..textRecordCount) {
                val record = stripTrailingData(records[recordIndex], extraDataFlags)
                output.write(if (compression == COMPRESSION_PALMDOC) decompressPalmDoc(record) else record)
                if (output.size() >= textLength) break
            }
            output.toByteArray().copyOf(minOf(output.size(), textLength))
        }
        val html = String(rawText, charset).replace("\u0000", "")
        val fallbackTitle = file.fileName.toString().removeSuffixIgnoreCase(".mobi").replace('_', ' ')
        val fullName = readFullName(header, charset)
        val title = exth.firstText(EXTH_UPDATED_TITLE, charset) ?: fullName ?: fallbackTitle
        val author = exth.textValues(EXTH_AUTHOR, charset).joinToString(", ").takeIf(String::isNotBlank)
        val description = exth.firstText(EXTH_DESCRIPTION, charset)
            ?.let { Jsoup.parse(it).text().normalizeWhitespace() }
            ?.takeIf(String::isNotBlank)
        val language = exth.firstText(EXTH_LANGUAGE, charset)
        val tags = buildList {
            add("mobi")
            exth.textValues(EXTH_SUBJECT, charset)
                .flatMap { it.split(',', ';') }
                .map(String::trim)
                .filter(String::isNotBlank)
                .let(::addAll)
        }.distinct()
        val metadata = BookMetadata(title, author, language, description, tags)
        val content = htmlToStructuredContent(html, title, images, firstImageIndex)
        return ParsedMobi(metadata, content, images, coverRecordIndex)
    }

    private fun htmlToStructuredContent(
        html: String,
        bookTitle: String,
        images: Map<Int, MobiImage>,
        firstImageIndex: Int?,
    ): StructuredBookContent {
        val normalizedHtml = html.replace(PAGE_BREAK_TAG, "<hr data-mobi-pagebreak=\"true\">")
        val document = Jsoup.parse(normalizedHtml)
        document.select("script, style, head").remove()
        val pendingChapters = mutableListOf<PendingChapter>()
        var currentTitle = bookTitle
        var currentBlocks = mutableListOf<PendingBlock>()

        fun flushChapter() {
            if (currentBlocks.isEmpty()) return
            pendingChapters += PendingChapter(currentTitle, currentBlocks.toList())
            currentBlocks = mutableListOf()
            currentTitle = ""
        }

        fun referencedImage(element: Element): MobiImage? {
            val rawIndex = listOf("recindex", "mediarecindex")
                .firstNotNullOfOrNull { attribute -> element.attr(attribute).trim().parseMobiImageIndex() }
                ?: KINDLE_EMBED.find(element.attr("src"))?.groupValues?.get(1)?.parseBase32()
                ?: return null
            val orderedImages = images.values.sortedBy(MobiImage::recordIndex)
            val candidates = listOf(rawIndex - 1, rawIndex).filter { it >= 0 }
            return candidates.firstNotNullOfOrNull { ordinal -> orderedImages.getOrNull(ordinal) }
                ?: firstImageIndex?.let { base -> images[base + rawIndex] }
        }

        fun imageBlock(element: Element): PendingBlock? {
            val image = referencedImage(element)
            val alt = element.attr("alt").normalizeWhitespace()
            if (image == null) {
                return alt.takeIf(String::isNotBlank)?.let { PendingBlock(StructuredBlockType.PARAGRAPH, it) }
            }
            return PendingBlock(
                type = StructuredBlockType.IMAGE,
                text = alt,
                meta = buildMap {
                    put("resourceId", encodeResourceId(image.recordIndex))
                    put("mediaType", image.mimeType)
                    put("src", "record:${image.recordIndex}")
                    alt.takeIf(String::isNotBlank)?.let { put("alt", it) }
                    element.attr("width").parseDimension()?.let { put("width", it) }
                    element.attr("height").parseDimension()?.let { put("height", it) }
                },
            )
        }

        fun collectInline(element: Element, type: StructuredBlockType) {
            val text = StringBuilder()
            fun flushText() {
                text.toString().normalizeWhitespace().takeIf(String::isNotBlank)?.let { currentBlocks += PendingBlock(type, it) }
                text.clear()
            }
            fun appendNode(node: Node) {
                when (node) {
                    is TextNode -> text.append(node.getWholeText())
                    is Element -> when (node.normalName()) {
                        "img" -> {
                            flushText()
                            imageBlock(node)?.let(currentBlocks::add)
                        }
                        "br" -> text.append(' ')
                        else -> node.childNodes().forEach(::appendNode)
                    }
                }
            }
            element.childNodes().forEach(::appendNode)
            flushText()
        }

        fun walk(element: Element) {
            when (element.normalName()) {
                "h1", "h2", "h3", "h4", "h5", "h6" -> {
                    val heading = element.text().normalizeWhitespace()
                    if (heading.isNotBlank()) {
                        if (currentBlocks.isNotEmpty()) flushChapter()
                        currentTitle = heading
                    }
                }
                "p", "li", "pre" -> collectInline(element, StructuredBlockType.PARAGRAPH)
                "blockquote" -> collectInline(element, StructuredBlockType.QUOTE)
                "img" -> imageBlock(element)?.let(currentBlocks::add)
                "hr" -> if (element.hasAttr("data-mobi-pagebreak")) {
                    flushChapter()
                } else {
                    currentBlocks += PendingBlock(StructuredBlockType.DIVIDER, "")
                }
                "body", "article", "section", "main", "div", "center", "table", "tbody", "tr", "td" -> {
                    if (element.children().isEmpty()) {
                        collectInline(element, StructuredBlockType.PARAGRAPH)
                    } else {
                        element.children().forEach(::walk)
                    }
                }
                else -> if (element.children().isEmpty()) {
                    collectInline(element, StructuredBlockType.PARAGRAPH)
                } else {
                    element.children().forEach(::walk)
                }
            }
        }

        document.body().children().forEach(::walk)
        flushChapter()
        if (pendingChapters.isEmpty()) {
            document.body().text().normalizeWhitespace().takeIf(String::isNotBlank)?.let { text ->
                pendingChapters += PendingChapter(bookTitle, listOf(PendingBlock(StructuredBlockType.PARAGRAPH, text)))
            }
        }
        val chapters = pendingChapters.mapIndexed { chapterIndex, chapter ->
            StructuredBookChapter(
                title = chapter.title.normalizeWhitespace().ifBlank { "Section ${chapterIndex + 1}" },
                anchor = chapterAnchor(chapterIndex),
                blocks = chapter.blocks.mapIndexed { blockIndex, block ->
                    StructuredBookBlock(
                        type = block.type,
                        anchor = blockAnchor(chapterIndex, blockIndex + 1),
                        text = block.text,
                        plainText = block.text,
                        meta = block.meta,
                    )
                },
            )
        }
        return StructuredBookContent(chapters, STRUCTURED_CONTENT_MODEL)
    }

    private fun readPalmRecords(bytes: ByteArray): List<ByteArray> {
        require(bytes.size >= PALM_HEADER_SIZE) { "MOBI file is too short" }
        val recordCount = bytes.u16(PALM_RECORD_COUNT_OFFSET)
        require(recordCount > 0) { "MOBI file has no Palm records" }
        val tableEnd = PALM_HEADER_SIZE + recordCount * PALM_RECORD_ENTRY_SIZE
        require(tableEnd <= bytes.size) { "MOBI Palm record table is truncated" }
        val offsets = (0 until recordCount).map { index ->
            bytes.u32(PALM_HEADER_SIZE + index * PALM_RECORD_ENTRY_SIZE).toIntChecked("Palm record offset")
        }
        require(offsets.zipWithNext().all { (left, right) -> left <= right } && offsets.all { it in tableEnd..bytes.size }) {
            "MOBI Palm record offsets are invalid"
        }
        return offsets.mapIndexed { index, start ->
            bytes.copyOfRange(start, offsets.getOrElse(index + 1) { bytes.size })
        }
    }

    private fun readExth(header: ByteArray, mobiHeaderLength: Int): ExthMetadata {
        val flags = header.u32OrNull(MOBI_START + EXTH_FLAGS_OFFSET) ?: return ExthMetadata(emptyMap())
        if (flags and EXTH_PRESENT_FLAG == 0L) return ExthMetadata(emptyMap())
        val start = MOBI_START + mobiHeaderLength
        if (start + 12 > header.size || header.ascii(start, 4) != "EXTH") return ExthMetadata(emptyMap())
        val totalLength = header.u32(start + 4).toIntChecked("EXTH length")
        val count = header.u32(start + 8).toIntChecked("EXTH record count")
        val end = (start + totalLength).coerceAtMost(header.size)
        var cursor = start + 12
        val records = linkedMapOf<Int, MutableList<ByteArray>>()
        repeat(count) {
            if (cursor + 8 > end) return@repeat
            val type = header.u32(cursor).toIntChecked("EXTH record type")
            val length = header.u32(cursor + 4).toIntChecked("EXTH record length")
            if (length < 8 || cursor + length > end) return@repeat
            records.getOrPut(type, ::mutableListOf) += header.copyOfRange(cursor + 8, cursor + length)
            cursor += length
        }
        return ExthMetadata(records)
    }

    private fun readFullName(header: ByteArray, charset: Charset): String? {
        val offset = header.u32OrNull(MOBI_START + FULL_NAME_OFFSET)?.toIntChecked("full name offset") ?: return null
        val length = header.u32OrNull(MOBI_START + FULL_NAME_LENGTH)?.toIntChecked("full name length") ?: return null
        if (length <= 0 || offset < 0 || offset + length > header.size) return null
        return String(header, offset, length, charset).normalizeWhitespace().takeIf(String::isNotBlank)
    }

    private fun extractImages(records: List<ByteArray>, firstImageIndex: Int?): Map<Int, MobiImage> {
        if (firstImageIndex == null || firstImageIndex !in records.indices) return emptyMap()
        return buildMap {
            for (recordIndex in firstImageIndex until records.size) {
                val record = records[recordIndex]
                detectImageMimeType(record)?.let { mimeType -> put(recordIndex, MobiImage(recordIndex, mimeType, record)) }
            }
        }
    }

    private fun decompressPalmDoc(input: ByteArray): ByteArray {
        var output = ByteArray((input.size * 2).coerceAtLeast(256))
        var outputSize = 0
        var cursor = 0

        fun ensureCapacity(additional: Int) {
            val required = outputSize + additional
            if (required <= output.size) return
            var nextSize = output.size
            while (nextSize < required) nextSize = Math.multiplyExact(nextSize, 2)
            output = output.copyOf(nextSize)
        }

        fun write(value: Int) {
            ensureCapacity(1)
            output[outputSize++] = value.toByte()
        }

        fun write(values: ByteArray, offset: Int, length: Int) {
            ensureCapacity(length)
            values.copyInto(output, outputSize, offset, offset + length)
            outputSize += length
        }

        while (cursor < input.size) {
            val value = input[cursor++].toInt() and 0xff
            when {
                value == 0 || value in 0x09..0x7f -> write(value)
                value in 0x01..0x08 -> {
                    require(cursor + value <= input.size) { "PalmDOC literal run is truncated" }
                    write(input, cursor, value)
                    cursor += value
                }
                value in 0x80..0xbf -> {
                    require(cursor < input.size) { "PalmDOC back-reference is truncated" }
                    val pair = (value shl 8) or (input[cursor++].toInt() and 0xff)
                    val distance = (pair and 0x3fff) shr 3
                    val length = (pair and 0x07) + 3
                    require(distance in 1..outputSize) { "PalmDOC back-reference is invalid" }
                    repeat(length) {
                        write(output[outputSize - distance].toInt())
                    }
                }
                else -> {
                    write(' '.code)
                    write(value xor 0x80)
                }
            }
        }
        return output.copyOf(outputSize)
    }

    private fun stripTrailingData(record: ByteArray, extraDataFlags: Int): ByteArray {
        var end = record.size
        var trailingEntryFlags = extraDataFlags ushr 1
        while (trailingEntryFlags != 0) {
            if (trailingEntryFlags and 1 != 0) {
                val entrySize = trailingEntrySize(record, end)
                require(entrySize in 1..end) { "MOBI trailing data entry is invalid" }
                end -= entrySize
            }
            trailingEntryFlags = trailingEntryFlags ushr 1
        }
        if (extraDataFlags and 1 != 0 && end > 0) {
            val overlapSize = (record[end - 1].u8() and 0x03) + 1
            require(overlapSize <= end) { "MOBI multibyte overlap data is invalid" }
            end -= overlapSize
        }
        return if (end == record.size) record else record.copyOf(end)
    }

    private fun trailingEntrySize(record: ByteArray, end: Int): Int {
        var size = 0
        var shift = 0
        for (distance in 1..minOf(4, end)) {
            val value = record[end - distance].u8()
            size = size or ((value and 0x7f) shl shift)
            if (value and 0x80 != 0) return size
            shift += 7
        }
        throw IllegalArgumentException("MOBI trailing data length is truncated")
    }

    private fun detectImageMimeType(bytes: ByteArray): String? = when {
        bytes.size >= 3 && bytes[0].u8() == 0xff && bytes[1].u8() == 0xd8 && bytes[2].u8() == 0xff -> "image/jpeg"
        bytes.size >= 8 && bytes.copyOfRange(0, 8).contentEquals(PNG_SIGNATURE) -> "image/png"
        bytes.size >= 6 && bytes.ascii(0, 6) in setOf("GIF87a", "GIF89a") -> "image/gif"
        bytes.size >= 12 && bytes.ascii(0, 4) == "RIFF" && bytes.ascii(8, 4) == "WEBP" -> "image/webp"
        bytes.size >= 2 && bytes.ascii(0, 2) == "BM" -> "image/bmp"
        else -> null
    }

    private fun mobiCharset(encoding: Long): Charset = when (encoding.toInt()) {
        65001 -> StandardCharsets.UTF_8
        1252 -> Charset.forName("windows-1252")
        else -> throw invalid("unsupported text encoding $encoding")
    }

    private fun encodeResourceId(recordIndex: Int): String = Base64.getUrlEncoder()
        .withoutPadding()
        .encodeToString("record:$recordIndex".toByteArray(StandardCharsets.UTF_8))

    private fun decodeResourceId(resourceId: String): Int? = runCatching {
        String(Base64.getUrlDecoder().decode(resourceId), StandardCharsets.UTF_8)
            .takeIf { it.startsWith("record:") }
            ?.removePrefix("record:")
            ?.toIntOrNull()
    }.getOrNull()

    private fun String.parseMobiImageIndex(): Int? = removePrefix("0x").let { value ->
        value.toIntOrNull() ?: value.toIntOrNull(16)
    }

    private fun String.parseBase32(): Int? = runCatching {
        uppercase().fold(0) { result, char ->
            val digit = BASE32_ALPHABET.indexOf(char)
            require(digit >= 0)
            Math.addExact(Math.multiplyExact(result, 32), digit)
        }
    }.getOrNull()

    private fun String.parseDimension(): Int? = trim().removeSuffix("px").substringBefore('.').toIntOrNull()?.takeIf { it > 0 }

    private fun ByteArray.u8(index: Int = 0): Int = this[index].toInt() and 0xff

    private fun Byte.u8(): Int = toInt() and 0xff

    private fun ByteArray.u16(offset: Int): Int {
        require(offset >= 0 && offset + 2 <= size) { "MOBI field is truncated" }
        return (this[offset].u8() shl 8) or this[offset + 1].u8()
    }

    private fun ByteArray.u32(offset: Int): Long {
        require(offset >= 0 && offset + 4 <= size) { "MOBI field is truncated" }
        return (this[offset].u8().toLong() shl 24) or
            (this[offset + 1].u8().toLong() shl 16) or
            (this[offset + 2].u8().toLong() shl 8) or
            this[offset + 3].u8().toLong()
    }

    private fun ByteArray.u32OrNull(offset: Int): Long? = if (offset >= 0 && offset + 4 <= size) u32(offset) else null

    private fun ByteArray.ascii(offset: Int, length: Int): String =
        if (offset >= 0 && offset + length <= size) String(this, offset, length, StandardCharsets.US_ASCII) else ""

    private fun Long.toIntChecked(label: String): Int {
        require(this in 0..Int.MAX_VALUE.toLong()) { "$label exceeds supported size" }
        return toInt()
    }

    private fun String.normalizeWhitespace(): String = replace('\u00a0', ' ').replace(Regex("\\s+"), " ").trim()

    private fun String.removeSuffixIgnoreCase(suffix: String): String =
        if (endsWith(suffix, ignoreCase = true)) dropLast(suffix.length) else this

    private fun chapterAnchor(index: Int): String = "chapter-$index"

    private fun blockAnchor(chapterIndex: Int, blockIndex: Int): String = "chapter-$chapterIndex-block-$blockIndex"

    private fun invalid(message: String): IllegalArgumentException = IllegalArgumentException("Invalid MOBI file: $message")

    private data class ParsedMobi(
        val metadata: BookMetadata,
        val content: StructuredBookContent,
        val images: Map<Int, MobiImage>,
        val coverRecordIndex: Int?,
    )

    private data class MobiImage(val recordIndex: Int, val mimeType: String, val bytes: ByteArray)

    private data class PendingChapter(val title: String, val blocks: List<PendingBlock>)

    private data class PendingBlock(
        val type: StructuredBlockType,
        val text: String,
        val meta: Map<String, Any?> = emptyMap(),
    )

    private data class ExthMetadata(val records: Map<Int, List<ByteArray>>) {
        fun textValues(type: Int, charset: Charset): List<String> = records[type].orEmpty()
            .map { String(it, charset).trimEnd('\u0000').replace('\u00a0', ' ').replace(Regex("\\s+"), " ").trim() }
            .filter(String::isNotBlank)

        fun firstText(type: Int, charset: Charset): String? = textValues(type, charset).firstOrNull()

        fun firstInt(type: Int): Int? {
            val bytes = records[type]?.firstOrNull()?.takeIf { it.size >= 4 } ?: return null
            val value = ((bytes[0].toInt() and 0xff).toLong() shl 24) or
                ((bytes[1].toInt() and 0xff).toLong() shl 16) or
                ((bytes[2].toInt() and 0xff).toLong() shl 8) or
                (bytes[3].toInt() and 0xff).toLong()
            return value.takeIf { it <= Int.MAX_VALUE }?.toInt()
        }
    }

    private companion object {
        private const val STRUCTURED_CONTENT_MODEL = "UNIFIED_V2"
        private const val MAX_INDEX_LENGTH = 50_000
        private const val PALM_HEADER_SIZE = 78
        private const val PALM_RECORD_COUNT_OFFSET = 76
        private const val PALM_RECORD_ENTRY_SIZE = 8
        private const val MOBI_START = 16
        private const val MIN_MOBI_HEADER_LENGTH = 116
        private const val COMPRESSION_NONE = 1
        private const val COMPRESSION_PALMDOC = 2
        private const val COMPRESSION_HUFF_CDIC = 17_480
        private const val FULL_NAME_OFFSET = 68
        private const val FULL_NAME_LENGTH = 72
        private const val FIRST_IMAGE_INDEX_OFFSET = 92
        private const val EXTH_FLAGS_OFFSET = 112
        private const val EXTRA_DATA_FLAGS_OFFSET = 226
        private const val EXTH_PRESENT_FLAG = 0x40L
        private const val EXTH_AUTHOR = 100
        private const val EXTH_SUBJECT = 105
        private const val EXTH_DESCRIPTION = 103
        private const val EXTH_COVER_OFFSET = 201
        private const val EXTH_UPDATED_TITLE = 503
        private const val EXTH_LANGUAGE = 524
        private const val UINT32_MAX = 0xffff_ffffL
        private const val BASE32_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUV"
        private val PAGE_BREAK_TAG = Regex("(?is)<\\s*(?:mbp:)?pagebreak\\b[^>]*?/?>")
        private val KINDLE_EMBED = Regex("(?i)kindle:embed:([0-9a-v]+)")
        private val PNG_SIGNATURE = byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)
    }
}
