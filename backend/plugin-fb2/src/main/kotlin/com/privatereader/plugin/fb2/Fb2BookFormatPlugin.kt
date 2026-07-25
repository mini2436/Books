package com.privatereader.plugin.fb2

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
import org.springframework.stereotype.Component
import org.w3c.dom.Document
import org.w3c.dom.Element
import org.w3c.dom.Node
import org.w3c.dom.NodeList
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.util.Base64
import javax.xml.XMLConstants
import javax.xml.parsers.DocumentBuilderFactory

@Component
class Fb2BookFormatPlugin : BookFormatPlugin {
    override val pluginId: String = "plugin-fb2"
    override val displayName: String = "FictionBook 2 Plugin"
    override val supportedExtensions: Set<String> = setOf("fb2")
    override val capabilities: Set<PluginCapability> = setOf(
        PluginCapability.READ_ONLINE,
        PluginCapability.EXTRACT_TOC,
        PluginCapability.EXTRACT_COVER,
        PluginCapability.FULL_TEXT_INDEX,
        PluginCapability.SUPPORTS_ANNOTATIONS,
    )

    override fun canHandle(file: Path): Boolean = file.fileName.toString().endsWith(".fb2", ignoreCase = true)

    override fun extractMetadata(file: Path): BookMetadata {
        val document = readDocument(file)
        val titleInfo = document.firstElement("title-info")
        val authors = titleInfo?.directChildren("author")
            ?.mapNotNull(::authorName)
            .orEmpty()
        val fallbackTitle = file.fileName.toString().removeSuffixIgnoreCase(".fb2").replace('_', ' ')
        return BookMetadata(
            title = titleInfo?.firstText("book-title") ?: fallbackTitle,
            author = authors.takeIf(List<String>::isNotEmpty)?.joinToString(", "),
            language = titleInfo?.firstText("lang"),
            description = titleInfo?.firstElement("annotation")?.textContent.normalizeWhitespace().takeIf(String::isNotBlank),
            tags = buildList {
                add("fb2")
                titleInfo?.directChildren("genre")
                    ?.mapNotNull { it.textContent.normalizeWhitespace().takeIf(String::isNotBlank) }
                    ?.let(::addAll)
            }.distinct(),
        )
    }

    override fun extractCover(file: Path): CoverExtractionResult? {
        val document = readDocument(file)
        val coverId = document.firstElement("coverpage")
            ?.firstElement("image")
            ?.imageHref()
            ?.removePrefix("#")
            ?.takeIf(String::isNotBlank)
            ?: return null
        val binary = extractBinaries(document)[coverId] ?: return null
        return CoverExtractionResult(mimeType = binary.mimeType, bytes = binary.bytes)
    }

    override fun extractResource(file: Path, resourceId: String): BookResource? {
        val binaryId = decodeResourceId(resourceId) ?: return null
        val binary = extractBinaries(readDocument(file))[binaryId] ?: return null
        return BookResource(mimeType = binary.mimeType, bytes = binary.bytes)
    }

    override fun buildManifest(file: Path): ReadingManifest {
        val content = extractStructuredContent(file)
        return ReadingManifest(
            format = "fb2",
            toc = content.chapters.map { chapter -> ManifestTocItem(chapter.title, chapter.anchor) },
            primaryLocation = content.chapters.firstOrNull()?.anchor ?: "chapter-0",
        )
    }

    override fun extractIndexableContent(file: Path): IndexableContent? {
        val text = extractStructuredContent(file).chapters
            .asSequence()
            .flatMap { chapter -> sequenceOf(chapter.title) + chapter.blocks.asSequence().map { it.plainText } }
            .joinToString(" ")
            .normalizeWhitespace()
            .take(MAX_INDEX_LENGTH)
        return text.takeIf(String::isNotBlank)?.let(::IndexableContent)
    }

    override fun extractStructuredContent(file: Path): StructuredBookContent {
        val document = readDocument(file)
        val binaries = extractBinaries(document)
        val bodies = document.getElementsByTagNameNS("*", "body").asSequence().mapNotNull { it as? Element }.toList()
        val body = bodies.firstOrNull { it.getAttribute("name").isBlank() } ?: bodies.firstOrNull()
            ?: return StructuredBookContent(emptyList(), STRUCTURED_CONTENT_MODEL)
        val pendingChapters = mutableListOf<PendingChapter>()
        val topLevelSections = body.directChildren("section")

        if (topLevelSections.isEmpty()) {
            pendingChapters += PendingChapter(
                title = extractMetadata(file).title,
                blocks = collectBlocks(body, binaries, skipNestedSections = false),
            )
        } else {
            topLevelSections.forEach { section -> collectSections(section, binaries, pendingChapters) }
        }

        val chapters = pendingChapters
            .filter { it.blocks.isNotEmpty() || it.title.isNotBlank() }
            .mapIndexed { chapterIndex, chapter ->
                val title = chapter.title.normalizeWhitespace().ifBlank { "Section ${chapterIndex + 1}" }
                StructuredBookChapter(
                    title = title,
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
        return StructuredBookContent(chapters = chapters, contentModel = STRUCTURED_CONTENT_MODEL)
    }

    private fun collectSections(
        section: Element,
        binaries: Map<String, Fb2Binary>,
        chapters: MutableList<PendingChapter>,
    ) {
        val title = section.directChildren("title")
            .firstOrNull()
            ?.directChildren("p")
            ?.joinToString(" ") { it.textContent.normalizeWhitespace() }
            .orEmpty()
        val blocks = collectBlocks(section, binaries, skipNestedSections = true)
        if (blocks.isNotEmpty()) {
            chapters += PendingChapter(title = title, blocks = blocks)
        }
        section.directChildren("section").forEach { nested -> collectSections(nested, binaries, chapters) }
    }

    private fun collectBlocks(
        root: Element,
        binaries: Map<String, Fb2Binary>,
        skipNestedSections: Boolean,
    ): List<PendingBlock> {
        val blocks = mutableListOf<PendingBlock>()

        fun addText(type: StructuredBlockType, value: String, meta: Map<String, Any?> = emptyMap()) {
            value.normalizeWhitespace().takeIf(String::isNotBlank)?.let { blocks += PendingBlock(type, it, meta) }
        }

        fun addImage(element: Element) {
            val id = element.imageHref().removePrefix("#").takeIf(String::isNotBlank) ?: return
            val binary = binaries[id] ?: return
            if (binary.mimeType !in SUPPORTED_IMAGE_TYPES) return
            val title = element.getAttribute("title").normalizeWhitespace()
            blocks += PendingBlock(
                type = StructuredBlockType.IMAGE,
                text = title,
                meta = buildMap {
                    put("resourceId", encodeResourceId(id))
                    put("mediaType", binary.mimeType)
                    put("src", id)
                    title.takeIf(String::isNotBlank)?.let { put("alt", it) }
                },
            )
        }

        fun walk(element: Element, inheritedType: StructuredBlockType = StructuredBlockType.PARAGRAPH) {
            when (element.localName?.lowercase() ?: element.tagName.lowercase()) {
                "section" -> if (!skipNestedSections || element === root) {
                    element.directElements().forEach { walk(it, inheritedType) }
                }

                "title" -> Unit
                "subtitle" -> addText(StructuredBlockType.HEADING, element.textContent, mapOf("level" to 2))
                "p", "v", "text-author", "date" -> {
                    val images = element.directChildren("image")
                    val text = element.textContent
                    addText(inheritedType, text)
                    images.forEach(::addImage)
                }

                "image" -> addImage(element)
                "empty-line" -> blocks += PendingBlock(StructuredBlockType.DIVIDER, "")
                "cite", "epigraph" -> element.directElements().forEach { walk(it, StructuredBlockType.QUOTE) }
                "poem", "stanza", "annotation" -> element.directElements().forEach { walk(it, inheritedType) }
                else -> element.directElements().forEach { walk(it, inheritedType) }
            }
        }

        root.directElements().forEach { child ->
            if (child.localName.equals("section", ignoreCase = true) && skipNestedSections) return@forEach
            walk(child)
        }
        return blocks
    }

    private fun extractBinaries(document: Document): Map<String, Fb2Binary> = buildMap {
        document.getElementsByTagNameNS("*", "binary").asSequence().forEach { node ->
            val element = node as? Element ?: return@forEach
            val id = element.getAttribute("id").trim().takeIf(String::isNotBlank) ?: return@forEach
            val mimeType = element.getAttribute("content-type").trim().lowercase().takeIf(String::isNotBlank)
                ?: "application/octet-stream"
            val bytes = runCatching { Base64.getMimeDecoder().decode(element.textContent) }.getOrNull()
                ?.takeIf(ByteArray::isNotEmpty)
                ?: return@forEach
            put(id, Fb2Binary(mimeType, bytes))
        }
    }

    private fun readDocument(file: Path): Document {
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
        return Files.newInputStream(file).use(factory.newDocumentBuilder()::parse)
    }

    private fun authorName(author: Element): String? {
        val nickname = author.firstText("nickname")
        val fullName = listOfNotNull(
            author.firstText("first-name"),
            author.firstText("middle-name"),
            author.firstText("last-name"),
        ).joinToString(" ").normalizeWhitespace()
        return fullName.takeIf(String::isNotBlank) ?: nickname
    }

    private fun Document.firstElement(localName: String): Element? =
        getElementsByTagNameNS("*", localName).item(0) as? Element

    private fun Element.firstElement(localName: String): Element? =
        getElementsByTagNameNS("*", localName).item(0) as? Element

    private fun Element.firstText(localName: String): String? = firstElement(localName)
        ?.textContent
        .normalizeWhitespace()
        .takeIf(String::isNotBlank)

    private fun Element.directElements(): List<Element> = childNodes.asSequence().mapNotNull { it as? Element }.toList()

    private fun Element.directChildren(localName: String): List<Element> = directElements()
        .filter { it.localName.equals(localName, ignoreCase = true) || it.tagName.equals(localName, ignoreCase = true) }

    private fun Element.imageHref(): String = getAttribute("l:href")
        .ifBlank { getAttribute("xlink:href") }
        .ifBlank { getAttributeNS("http://www.w3.org/1999/xlink", "href") }
        .trim()

    private fun encodeResourceId(id: String): String = Base64.getUrlEncoder()
        .withoutPadding()
        .encodeToString(id.toByteArray(StandardCharsets.UTF_8))

    private fun decodeResourceId(resourceId: String): String? = runCatching {
        String(Base64.getUrlDecoder().decode(resourceId), StandardCharsets.UTF_8)
    }.getOrNull()?.takeIf(String::isNotBlank)

    private fun NodeList.asSequence(): Sequence<Node> = sequence {
        for (index in 0 until length) yield(item(index))
    }

    private fun String?.normalizeWhitespace(): String = orEmpty()
        .replace('\u00a0', ' ')
        .replace(Regex("\\s+"), " ")
        .trim()

    private fun String.removeSuffixIgnoreCase(suffix: String): String =
        if (endsWith(suffix, ignoreCase = true)) dropLast(suffix.length) else this

    private fun chapterAnchor(index: Int): String = "chapter-$index"

    private fun blockAnchor(chapterIndex: Int, blockIndex: Int): String = "chapter-$chapterIndex-block-$blockIndex"

    private data class Fb2Binary(val mimeType: String, val bytes: ByteArray)

    private data class PendingChapter(val title: String, val blocks: List<PendingBlock>)

    private data class PendingBlock(
        val type: StructuredBlockType,
        val text: String,
        val meta: Map<String, Any?> = emptyMap(),
    )

    private companion object {
        private const val STRUCTURED_CONTENT_MODEL = "UNIFIED_V2"
        private const val MAX_INDEX_LENGTH = 50_000
        private val SUPPORTED_IMAGE_TYPES = setOf("image/jpeg", "image/png", "image/webp", "image/gif")
    }
}
