package com.privatereader.plugin.cbz

import com.privatereader.plugin.BookFormatPlugin
import com.privatereader.plugin.BookMetadata
import com.privatereader.plugin.BookResource
import com.privatereader.plugin.CoverExtractionResult
import com.privatereader.plugin.ManifestTocItem
import com.privatereader.plugin.PluginCapability
import com.privatereader.plugin.ReadingManifest
import com.privatereader.plugin.StructuredBlockType
import com.privatereader.plugin.StructuredBookBlock
import com.privatereader.plugin.StructuredBookChapter
import com.privatereader.plugin.StructuredBookContent
import org.springframework.stereotype.Component
import org.w3c.dom.Document
import java.io.ByteArrayInputStream
import java.nio.charset.StandardCharsets
import java.nio.file.Path
import java.util.Base64
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import javax.xml.XMLConstants
import javax.xml.parsers.DocumentBuilderFactory

@Component
class CbzBookFormatPlugin : BookFormatPlugin {
    override val pluginId: String = "plugin-cbz"
    override val displayName: String = "CBZ Comic Plugin"
    override val supportedExtensions: Set<String> = setOf("cbz")
    override val capabilities: Set<PluginCapability> = setOf(
        PluginCapability.READ_ONLINE,
        PluginCapability.EXTRACT_TOC,
        PluginCapability.EXTRACT_COVER,
        PluginCapability.SUPPORTS_ANNOTATIONS,
    )

    override fun canHandle(file: Path): Boolean = file.fileName.toString().endsWith(".cbz", ignoreCase = true)

    override fun extractMetadata(file: Path): BookMetadata = ZipFile(file.toFile()).use { zip ->
        val comicInfo = readComicInfo(zip)
        val fallbackTitle = file.fileName.toString().removeSuffixIgnoreCase(".cbz").replace('_', ' ')
        BookMetadata(
            title = comicInfo?.text("Title") ?: comicInfo?.text("Series") ?: fallbackTitle,
            author = comicInfo?.text("Writer")
                ?: comicInfo?.text("Penciller")
                ?: comicInfo?.text("Creator"),
            language = comicInfo?.text("LanguageISO"),
            description = comicInfo?.text("Summary"),
            tags = buildList {
                add("cbz")
                comicInfo?.text("Genre")
                    ?.split(',', ';')
                    ?.map(String::trim)
                    ?.filter(String::isNotBlank)
                    ?.let(::addAll)
            }.distinct(),
        )
    }

    override fun extractCover(file: Path): CoverExtractionResult? = ZipFile(file.toFile()).use { zip ->
        val pages = imageEntries(zip)
        val declaredCoverIndex = readComicInfo(zip)?.frontCoverIndex()
        val entry = declaredCoverIndex?.let(pages::getOrNull) ?: pages.firstOrNull() ?: return null
        val bytes = zip.getInputStream(entry).use { it.readBytes() }
        bytes.takeIf(ByteArray::isNotEmpty)?.let {
            CoverExtractionResult(mimeType = mimeType(entry.name), bytes = it)
        }
    }

    override fun extractResource(file: Path, resourceId: String): BookResource? = ZipFile(file.toFile()).use { zip ->
        val requestedPath = decodeResourceId(resourceId) ?: return null
        val entry = imageEntries(zip).firstOrNull { it.name.normalizedEntryName() == requestedPath } ?: return null
        val bytes = zip.getInputStream(entry).use { it.readBytes() }
        bytes.takeIf(ByteArray::isNotEmpty)?.let {
            BookResource(mimeType = mimeType(entry.name), bytes = it)
        }
    }

    override fun buildManifest(file: Path): ReadingManifest = ZipFile(file.toFile()).use { zip ->
        val pages = imageEntries(zip)
        ReadingManifest(
            format = "cbz",
            toc = pages.mapIndexed { index, _ ->
                ManifestTocItem(title = "Page ${index + 1}", href = chapterAnchor(index))
            },
            primaryLocation = pages.indices.firstOrNull()?.let(::chapterAnchor) ?: "chapter-0",
            meta = mapOf("pageCount" to pages.size),
        )
    }

    override fun extractStructuredContent(file: Path): StructuredBookContent = ZipFile(file.toFile()).use { zip ->
        val chapters = imageEntries(zip).mapIndexed { pageIndex, entry ->
            val normalizedPath = entry.name.normalizedEntryName()
            StructuredBookChapter(
                title = "Page ${pageIndex + 1}",
                anchor = chapterAnchor(pageIndex),
                blocks = listOf(
                    StructuredBookBlock(
                        type = StructuredBlockType.IMAGE,
                        anchor = blockAnchor(pageIndex, 1),
                        text = "Page ${pageIndex + 1}",
                        plainText = "Page ${pageIndex + 1}",
                        meta = mapOf(
                            "resourceId" to encodeResourceId(normalizedPath),
                            "mediaType" to mimeType(normalizedPath),
                            "src" to normalizedPath,
                            "alt" to "Page ${pageIndex + 1}",
                            "pageNumber" to pageIndex + 1,
                        ),
                    ),
                ),
            )
        }
        StructuredBookContent(chapters = chapters, contentModel = STRUCTURED_CONTENT_MODEL)
    }

    private fun imageEntries(zip: ZipFile): List<ZipEntry> = zip.entries().asSequence()
        .filterNot(ZipEntry::isDirectory)
        .filter { entry ->
            val path = entry.name.normalizedEntryName()
            !path.startsWith("__MACOSX/") &&
                !path.substringAfterLast('/').startsWith('.') &&
                path.substringAfterLast('.', "").lowercase() in SUPPORTED_EXTENSIONS
        }
        .sortedWith { left, right -> naturalCompare(left.name, right.name) }
        .toList()

    private fun readComicInfo(zip: ZipFile): Document? {
        val entry = zip.entries().asSequence()
            .firstOrNull { !it.isDirectory && it.name.substringAfterLast('/').equals("ComicInfo.xml", ignoreCase = true) }
            ?: return null
        return runCatching {
            val bytes = zip.getInputStream(entry).use { it.readBytes() }
            parseXml(bytes)
        }.getOrNull()
    }

    private fun parseXml(bytes: ByteArray): Document {
        val factory = DocumentBuilderFactory.newInstance()
        factory.isNamespaceAware = true
        factory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
        factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
        factory.setFeature("http://xml.org/sax/features/external-general-entities", false)
        factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false)
        factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "")
        factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "")
        factory.isXIncludeAware = false
        factory.isExpandEntityReferences = false
        return ByteArrayInputStream(bytes).use(factory.newDocumentBuilder()::parse)
    }

    private fun Document.text(name: String): String? = getElementsByTagName(name)
        .item(0)
        ?.textContent
        ?.normalizeWhitespace()
        ?.takeIf(String::isNotBlank)

    private fun Document.frontCoverIndex(): Int? {
        val pages = getElementsByTagName("Page")
        for (index in 0 until pages.length) {
            val page = pages.item(index) as? org.w3c.dom.Element ?: continue
            if (page.getAttribute("Type").contains("FrontCover", ignoreCase = true)) {
                return page.getAttribute("Image").toIntOrNull()?.takeIf { it >= 0 }
            }
        }
        return null
    }

    private fun encodeResourceId(path: String): String = Base64.getUrlEncoder()
        .withoutPadding()
        .encodeToString(path.toByteArray(StandardCharsets.UTF_8))

    private fun decodeResourceId(resourceId: String): String? = runCatching {
        String(Base64.getUrlDecoder().decode(resourceId), StandardCharsets.UTF_8).normalizedEntryName()
    }.getOrNull()?.takeIf { it.isNotBlank() && !it.startsWith('/') && ".." !in it.split('/') }

    private fun naturalCompare(left: String, right: String): Int {
        val leftParts = NATURAL_PART.findAll(left.lowercase()).map { it.value }.toList()
        val rightParts = NATURAL_PART.findAll(right.lowercase()).map { it.value }.toList()
        for (index in 0 until minOf(leftParts.size, rightParts.size)) {
            val leftPart = leftParts[index]
            val rightPart = rightParts[index]
            val result = if (leftPart.all(Char::isDigit) && rightPart.all(Char::isDigit)) {
                leftPart.trimStart('0').ifEmpty { "0" }.compareNumericString(rightPart.trimStart('0').ifEmpty { "0" })
            } else {
                leftPart.compareTo(rightPart)
            }
            if (result != 0) return result
        }
        return leftParts.size.compareTo(rightParts.size).takeIf { it != 0 } ?: left.compareTo(right, ignoreCase = true)
    }

    private fun String.compareNumericString(other: String): Int =
        length.compareTo(other.length).takeIf { it != 0 } ?: compareTo(other)

    private fun mimeType(path: String): String = when (path.substringAfterLast('.', "").lowercase()) {
        "jpg", "jpeg" -> "image/jpeg"
        "png" -> "image/png"
        "webp" -> "image/webp"
        "gif" -> "image/gif"
        else -> "application/octet-stream"
    }

    private fun String.normalizedEntryName(): String = replace('\\', '/').removePrefix("./")

    private fun String.removeSuffixIgnoreCase(suffix: String): String =
        if (endsWith(suffix, ignoreCase = true)) dropLast(suffix.length) else this

    private fun String.normalizeWhitespace(): String = replace('\u00a0', ' ').replace(Regex("\\s+"), " ").trim()

    private fun chapterAnchor(index: Int): String = "chapter-$index"

    private fun blockAnchor(chapterIndex: Int, blockIndex: Int): String = "chapter-$chapterIndex-block-$blockIndex"

    private companion object {
        private const val STRUCTURED_CONTENT_MODEL = "UNIFIED_V2"
        private val SUPPORTED_EXTENSIONS = setOf("jpg", "jpeg", "png", "webp", "gif")
        private val NATURAL_PART = Regex("\\d+|\\D+")
    }
}
