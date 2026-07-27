package com.privatereader.plugin.epub

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
import java.io.ByteArrayInputStream
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.nio.file.Path
import java.util.Base64
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import javax.xml.XMLConstants
import javax.xml.parsers.DocumentBuilderFactory

@Component
class EpubBookFormatPlugin : BookFormatPlugin {
    override val pluginId: String = "plugin-epub"
    override val displayName: String = "EPUB Plugin"
    override val supportedExtensions: Set<String> = setOf("epub")
    override val capabilities: Set<PluginCapability> = setOf(
        PluginCapability.READ_ONLINE,
        PluginCapability.EXTRACT_TOC,
        PluginCapability.EXTRACT_COVER,
        PluginCapability.FULL_TEXT_INDEX,
        PluginCapability.SUPPORTS_ANNOTATIONS,
    )

    override fun canHandle(file: Path): Boolean = file.fileName.toString().endsWith(".epub", ignoreCase = true)

    override fun extractMetadata(file: Path): BookMetadata = parse(file).metadata

    override fun extractCover(file: Path): CoverExtractionResult? = ZipFile(file.toFile()).use { zip ->
        val packagePath = readPackagePath(zip)
        val packageDocument = readXml(zip, packagePath)
        val packageDir = packagePath.substringBeforeLast('/', "")
        val manifestItems = extractManifestItems(packageDocument, packageDir)
        val coverItem = findCoverItem(packageDocument, manifestItems, packagePath)
        val resolvedCover = coverItem?.let { resolveCoverImage(zip, it, manifestItems) }
        val entry = resolvedCover?.let { zip.getEntry(it.path) }
            ?: findConventionalCoverEntry(zip)
            ?: return null
        val bytes = zip.getInputStream(entry).use { it.readBytes() }
        if (bytes.isEmpty()) {
            return null
        }
        val mimeType = detectImageMimeType(
            bytes = bytes,
            path = entry.name,
            declaredMimeType = resolvedCover?.mediaType,
        ) ?: return null
        CoverExtractionResult(
            mimeType = mimeType,
            bytes = bytes,
        )
    }

    /**
     * EPUB 2 books often point the guide cover at an XHTML title page rather than
     * at the image itself. Follow image references in XHTML/SVG wrappers instead
     * of accidentally storing the wrapper document as the cover.
     */
    private fun resolveCoverImage(
        zip: ZipFile,
        item: EpubManifestItem,
        manifestItems: Map<String, EpubManifestItem>,
        visitedPaths: Set<String> = emptySet(),
    ): CoverArchiveItem? {
        if (item.fullPath in visitedPaths) return null
        val declaredMimeType = item.mediaType.ifBlank { inferMimeTypeFromPath(item.fullPath) }
        if (declaredMimeType.startsWith("image/") && declaredMimeType != "image/svg+xml") {
            return CoverArchiveItem(item.fullPath, declaredMimeType)
        }
        if (!isCoverWrapper(declaredMimeType, item.fullPath)) return null

        val document = runCatching { readXml(zip, item.fullPath) }.getOrNull() ?: return null
        val imageElements = sequence {
            yieldAll(document.getElementsByTagNameNS("*", "img").asSequence())
            yieldAll(document.getElementsByTagNameNS("*", "image").asSequence())
        }
        for (node in imageElements) {
            val image = node as? Element ?: continue
            val href = image.getAttribute("src")
                .ifBlank { image.getAttribute("href") }
                .ifBlank { image.getAttribute("xlink:href") }
                .ifBlank { image.getAttributeNS("http://www.w3.org/1999/xlink", "href") }
                .trim()
            if (href.isBlank() || href.startsWith("data:", ignoreCase = true)) continue
            val resolvedPath = resolveHref(item.fullPath, href).substringBefore('#')
            val nestedItem = manifestItems.values.firstOrNull { it.fullPath == resolvedPath }
            if (nestedItem != null) {
                resolveCoverImage(zip, nestedItem, manifestItems, visitedPaths + item.fullPath)?.let { return it }
            }
            val entry = zip.getEntry(resolvedPath) ?: continue
            if (!entry.isDirectory && inferMimeTypeFromPath(entry.name).startsWith("image/")) {
                return CoverArchiveItem(entry.name, inferMimeTypeFromPath(entry.name))
            }
        }
        return null
    }

    private fun findConventionalCoverEntry(zip: ZipFile): ZipEntry? =
        zip.entries().asSequence()
            .filterNot { entry -> entry.isDirectory }
            .filter { entry -> inferMimeTypeFromPath(entry.name).startsWith("image/") }
            .filter { entry -> entry.name.contains("cover", ignoreCase = true) }
            .sortedBy { entry ->
                val fileName = entry.name.substringAfterLast('/').substringBeforeLast('.').lowercase()
                when {
                    fileName == "cover" -> 0
                    fileName.startsWith("cover") -> 1
                    else -> 2
                }
            }
            .firstOrNull()

    private fun isCoverWrapper(mediaType: String, path: String): Boolean =
        mediaType.contains("html", ignoreCase = true) ||
            mediaType == "image/svg+xml" ||
            path.endsWith(".xhtml", ignoreCase = true) ||
            path.endsWith(".html", ignoreCase = true) ||
            path.endsWith(".svg", ignoreCase = true)

    private fun detectImageMimeType(bytes: ByteArray, path: String, declaredMimeType: String?): String? {
        val declared = declaredMimeType.orEmpty().lowercase().takeIf { it.startsWith("image/") }
        val inferred = inferMimeTypeFromPath(path).takeIf { it.startsWith("image/") }
        return when {
            bytes.size >= 3 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte() && bytes[2] == 0xFF.toByte() -> "image/jpeg"
            bytes.size >= 8 && bytes.copyOfRange(0, 8).contentEquals(PNG_SIGNATURE) -> "image/png"
            bytes.size >= 6 && String(bytes, 0, 6, StandardCharsets.US_ASCII).startsWith("GIF8") -> "image/gif"
            bytes.size >= 12 && String(bytes, 0, 4, StandardCharsets.US_ASCII) == "RIFF" &&
                String(bytes, 8, 4, StandardCharsets.US_ASCII) == "WEBP" -> "image/webp"
            declared != null -> declared
            else -> inferred
        }
    }

    override fun extractResource(file: Path, resourceId: String): BookResource? = ZipFile(file.toFile()).use { zip ->
        val requestedPath = decodeResourceId(resourceId) ?: return null
        val packagePath = readPackagePath(zip)
        val packageDocument = readXml(zip, packagePath)
        val packageDir = packagePath.substringBeforeLast('/', "")
        val manifestItems = extractManifestItems(packageDocument, packageDir)
        val resourceItem = manifestItems.values.firstOrNull { item ->
            item.fullPath == requestedPath &&
                item.mediaType in SUPPORTED_IMAGE_MEDIA_TYPES
        } ?: return null
        val entry = zip.getEntry(resourceItem.fullPath) ?: return null
        val bytes = zip.getInputStream(entry).use { it.readBytes() }
        if (bytes.isEmpty()) {
            return null
        }
        BookResource(
            mimeType = resourceItem.mediaType.ifBlank { inferMimeTypeFromPath(resourceItem.fullPath) },
            bytes = bytes,
        )
    }

    override fun buildManifest(file: Path): ReadingManifest = parse(file).manifest

    override fun extractIndexableContent(file: Path): IndexableContent? =
        parse(file).indexExcerpt.takeIf { it.isNotBlank() }?.let { IndexableContent(text = it) }

    override fun extractStructuredContent(file: Path): StructuredBookContent = ZipFile(file.toFile()).use { zip ->
        val packagePath = readPackagePath(zip)
        val packageDocument = readXml(zip, packagePath)
        val packageDir = packagePath.substringBeforeLast('/', "")
        val manifestItems = extractManifestItems(packageDocument, packageDir)
        val spineItems = extractSpineItems(packageDocument, manifestItems)
        val imageItemsByPath = manifestItems.values
            .filter { it.mediaType in SUPPORTED_IMAGE_MEDIA_TYPES }
            .associateBy { it.fullPath }
        val tocByPath = extractToc(zip, packagePath, packageDocument, manifestItems)
            .groupBy { it.href.substringBefore('#') }

        val chapters = spineItems.mapIndexed { chapterIndex, spineItem ->
            val document = readXml(zip, spineItem.fullPath)
            val visibleBlocks = extractStructuredBlocks(
                document = document,
                chapterIndex = chapterIndex,
                chapterPath = spineItem.fullPath,
                imageItemsByPath = imageItemsByPath,
            )
            val fallbackText = document.documentElement?.textContent.normalizeWhitespace()
            val chapterTitle = tocByPath[spineItem.fullPath]?.firstOrNull()?.title
                ?: visibleBlocks.firstOrNull { it.type == StructuredBlockType.HEADING }?.plainText
                ?: "Section ${chapterIndex + 1}"
            StructuredBookChapter(
                title = chapterTitle,
                anchor = chapterAnchor(chapterIndex),
                blocks = visibleBlocks
                    .dropWhile { block ->
                        block.type == StructuredBlockType.HEADING &&
                            block.plainText.equals(chapterTitle, ignoreCase = true)
                    }
                    .ifEmpty {
                        fallbackText.takeIf { !it.isNullOrBlank() }?.let {
                            listOf(
                                StructuredBookBlock(
                                    type = StructuredBlockType.PARAGRAPH,
                                    anchor = blockAnchor(chapterIndex, 1),
                                    text = it,
                                    plainText = it,
                                ),
                            )
                        } ?: emptyList()
                    },
            )
        }

        StructuredBookContent(chapters = chapters, contentModel = STRUCTURED_CONTENT_MODEL_V2)
    }

    private fun parse(file: Path): ParsedEpub = ZipFile(file.toFile()).use { zip ->
        val packagePath = readPackagePath(zip)
        val packageDocument = readXml(zip, packagePath)
        val packageDir = packagePath.substringBeforeLast('/', "")
        val metadata = extractMetadata(packageDocument, file)
        val manifestItems = extractManifestItems(packageDocument, packageDir)
        val spineHrefs = extractSpineHrefs(packageDocument, manifestItems)
        val toc = extractToc(zip, packagePath, packageDocument, manifestItems)
        val primaryLocation = toc.firstOrNull()?.href ?: spineHrefs.firstOrNull() ?: packagePath
        val indexExcerpt = extractIndexText(zip, manifestItems, spineHrefs)
        ParsedEpub(
            metadata = metadata,
            manifest = ReadingManifest(
                format = "epub",
                toc = toc,
                primaryLocation = primaryLocation,
            ),
            indexExcerpt = indexExcerpt,
        )
    }

    private fun readPackagePath(zip: ZipFile): String {
        val container = readXml(zip, "META-INF/container.xml")
        val rootFiles = container.getElementsByTagNameNS("*", "rootfile")
        val rootFile = rootFiles.item(0) as? Element
            ?: throw IllegalArgumentException("EPUB container is missing META-INF/container.xml rootfile")
        return rootFile.getAttribute("full-path")
            .takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("EPUB container did not provide an OPF package path")
    }

    private fun extractMetadata(document: Document, file: Path): BookMetadata {
        val title = firstText(document, "title")
            ?: file.fileName.toString().removeSuffix(".epub")
        return BookMetadata(
            title = title,
            author = firstText(document, "creator"),
            language = firstText(document, "language"),
            description = firstText(document, "description"),
            tags = listOf("epub"),
        )
    }

    private fun findCoverItem(
        document: Document,
        manifestItems: Map<String, EpubManifestItem>,
        packagePath: String,
    ): EpubManifestItem? {
        val metaNodes = document.getElementsByTagNameNS("*", "meta")
        for (index in 0 until metaNodes.length) {
            val meta = metaNodes.item(index) as? Element ?: continue
            val name = meta.getAttribute("name").trim()
            if (!name.equals("cover", ignoreCase = true)) {
                continue
            }
            val coverId = meta.getAttribute("content").trim()
            if (coverId.isNotBlank()) {
                return manifestItems[coverId]
            }
        }

        manifestItems.values.firstOrNull { "cover-image" in it.properties }?.let { return it }

        val guideNodes = document.getElementsByTagNameNS("*", "reference")
        for (index in 0 until guideNodes.length) {
            val reference = guideNodes.item(index) as? Element ?: continue
            val type = reference.getAttribute("type").trim()
            if (!type.equals("cover", ignoreCase = true)) {
                continue
            }
            val href = reference.getAttribute("href").trim()
            if (href.isBlank()) {
                continue
            }
            val resolved = resolveHref(packagePath, href)
            manifestItems.values.firstOrNull { it.fullPath == resolved.substringBefore('#') }?.let { return it }
        }

        return manifestItems.values.firstOrNull { item ->
            item.mediaType.startsWith("image/") &&
                (item.id.contains("cover", ignoreCase = true) || item.href.contains("cover", ignoreCase = true))
        }
    }

    private fun extractManifestItems(document: Document, packageDir: String): Map<String, EpubManifestItem> {
        val items = linkedMapOf<String, EpubManifestItem>()
        val manifestNodes = document.getElementsByTagNameNS("*", "item")
        for (index in 0 until manifestNodes.length) {
            val element = manifestNodes.item(index) as? Element ?: continue
            val id = element.getAttribute("id").trim()
            val href = element.getAttribute("href").trim()
            if (id.isBlank() || href.isBlank()) {
                continue
            }
            items[id] = EpubManifestItem(
                id = id,
                href = href,
                fullPath = resolveEntryPath(packageDir, href),
                mediaType = element.getAttribute("media-type").trim(),
                properties = element.getAttribute("properties")
                    .split(' ')
                    .map { it.trim() }
                    .filter { it.isNotBlank() }
                    .toSet(),
            )
        }
        return items
    }

    private fun extractSpineHrefs(document: Document, manifestItems: Map<String, EpubManifestItem>): List<String> =
        extractSpineItems(document, manifestItems).map { it.fullPath }

    private fun extractSpineItems(document: Document, manifestItems: Map<String, EpubManifestItem>): List<EpubManifestItem> {
        val spineNodes = document.getElementsByTagNameNS("*", "itemref")
        val items = mutableListOf<EpubManifestItem>()
        for (index in 0 until spineNodes.length) {
            val element = spineNodes.item(index) as? Element ?: continue
            val idRef = element.getAttribute("idref").trim()
            val item = manifestItems[idRef] ?: continue
            items += item
        }
        return items
    }

    private fun extractToc(
        zip: ZipFile,
        packagePath: String,
        document: Document,
        manifestItems: Map<String, EpubManifestItem>,
    ): List<ManifestTocItem> {
        val spineHrefs = extractSpineHrefs(document, manifestItems)
        val candidates = mutableListOf<TocCandidate>()
        val navItem = manifestItems.values.firstOrNull { "nav" in it.properties }
        if (navItem != null) {
            val navToc = runCatching { parseHtmlToc(zip, navItem) }.getOrDefault(emptyList())
            if (navToc.isNotEmpty()) {
                candidates += evaluateTocCandidate(
                    zip = zip,
                    items = navToc,
                    spineHrefs = spineHrefs,
                    sourcePriority = TOC_PRIORITY_EPUB3_NAV,
                )
            }
        }

        val spine = document.getElementsByTagNameNS("*", "spine").item(0) as? Element
        val tocId = spine?.getAttribute("toc")?.trim().orEmpty()
        val ncxItem = manifestItems[tocId]
            ?: manifestItems.values.firstOrNull { item ->
                item.mediaType == "application/x-dtbncx+xml" || item.fullPath.endsWith(".ncx", ignoreCase = true)
            }
        if (ncxItem != null) {
            val ncxToc = runCatching { parseNcxToc(zip, ncxItem) }.getOrDefault(emptyList())
            if (ncxToc.isNotEmpty()) {
                candidates += evaluateTocCandidate(
                    zip = zip,
                    items = ncxToc,
                    spineHrefs = spineHrefs,
                    sourcePriority = TOC_PRIORITY_NCX,
                )
            }
        }

        val guideToc = runCatching { parseGuideToc(zip, packagePath, document) }.getOrDefault(emptyList())
        if (guideToc.isNotEmpty()) {
            candidates += evaluateTocCandidate(
                zip = zip,
                items = guideToc,
                spineHrefs = spineHrefs,
                sourcePriority = TOC_PRIORITY_GUIDE,
            )
        }

        val selected = candidates
            .filter { it.items.isNotEmpty() }
            .maxWithOrNull(compareBy<TocCandidate> { it.score }.thenBy { it.sourcePriority })
        if (selected != null) {
            return selected.items
        }

        return spineHrefs
            .take(12)
            .mapIndexed { index, href -> ManifestTocItem(title = "Section ${index + 1}", href = href) }
    }

    private fun parseHtmlToc(zip: ZipFile, navItem: EpubManifestItem): List<ManifestTocItem> {
        val document = readXml(zip, navItem.fullPath)
        val navNodes = document.getElementsByTagNameNS("*", "nav")
        val items = mutableListOf<ManifestTocItem>()
        for (index in 0 until navNodes.length) {
            val nav = navNodes.item(index) as? Element ?: continue
            val navType = nav.getAttribute("epub:type")
                .ifBlank { nav.getAttributeNS("http://www.idpf.org/2007/ops", "type") }
                .ifBlank { nav.getAttribute("type") }
            if (!navType.contains("toc", ignoreCase = true)) {
                continue
            }
            val anchors = nav.getElementsByTagNameNS("*", "a")
            for (anchorIndex in 0 until anchors.length) {
                val anchor = anchors.item(anchorIndex) as? Element ?: continue
                val href = anchor.getAttribute("href").trim()
                val title = anchor.textContent.normalizeWhitespace()
                if (href.isBlank() || title.isBlank()) {
                    continue
                }
                if (!isExternalReference(href)) {
                    items += ManifestTocItem(
                        title = title,
                        href = resolveHref(navItem.fullPath, href),
                    )
                }
            }
            if (items.isNotEmpty()) {
                return deduplicateTocItems(items)
            }
        }
        return emptyList()
    }

    private fun parseNcxToc(zip: ZipFile, ncxItem: EpubManifestItem): List<ManifestTocItem> {
        val document = readXml(zip, ncxItem.fullPath)
        val navPoints = document.getElementsByTagNameNS("*", "navPoint")
        val items = mutableListOf<ManifestTocItem>()
        for (index in 0 until navPoints.length) {
            val navPoint = navPoints.item(index) as? Element ?: continue
            val label = navPoint.getElementsByTagNameNS("*", "text").item(0)?.textContent.normalizeWhitespace()
            val content = navPoint.getElementsByTagNameNS("*", "content").item(0) as? Element
            val src = content?.getAttribute("src")?.trim().orEmpty()
            if (label.isNullOrBlank() || src.isBlank()) {
                continue
            }
            if (!isExternalReference(src)) {
                items += ManifestTocItem(
                    title = label,
                    href = resolveHref(ncxItem.fullPath, src),
                )
            }
        }
        return deduplicateTocItems(items)
    }

    private fun parseGuideToc(zip: ZipFile, packagePath: String, packageDocument: Document): List<ManifestTocItem> {
        val references = packageDocument.getElementsByTagNameNS("*", "reference")
        for (index in 0 until references.length) {
            val reference = references.item(index) as? Element ?: continue
            val types = reference.getAttribute("type")
                .lowercase()
                .split(Regex("\\s+"))
                .filter { it.isNotBlank() }
            if ("toc" !in types) {
                continue
            }
            val href = reference.getAttribute("href").trim()
            if (href.isBlank() || isExternalReference(href)) {
                continue
            }
            val guidePath = resolveHref(packagePath, href).substringBefore('#')
            val guideDocument = readXml(zip, guidePath)
            val anchors = guideDocument.getElementsByTagNameNS("*", "a")
            val items = mutableListOf<ManifestTocItem>()
            for (anchorIndex in 0 until anchors.length) {
                val anchor = anchors.item(anchorIndex) as? Element ?: continue
                val target = anchor.getAttribute("href").trim()
                val title = anchor.textContent.normalizeWhitespace()
                if (target.isBlank() || title.isBlank() || isExternalReference(target)) {
                    continue
                }
                items += ManifestTocItem(
                    title = title,
                    href = resolveHref(guidePath, target),
                )
            }
            if (items.isNotEmpty()) {
                return deduplicateTocItems(items)
            }
        }
        return emptyList()
    }

    private fun evaluateTocCandidate(
        zip: ZipFile,
        items: List<ManifestTocItem>,
        spineHrefs: List<String>,
        sourcePriority: Int,
    ): TocCandidate {
        val deduplicated = deduplicateTocItems(items)
        val documentCache = mutableMapOf<String, Document?>()
        val validItems = deduplicated.filter { item -> tocTargetExists(zip, item.href, documentCache) }
        val validity = if (deduplicated.isEmpty()) 0.0 else validItems.size.toDouble() / deduplicated.size
        val spineIndex = spineHrefs.withIndex().associate { (index, href) -> href.substringBefore('#') to index }
        val targetIndices = validItems.mapNotNull { item -> spineIndex[item.href.substringBefore('#')] }
        val monotonicity = if (targetIndices.size < 2) {
            1.0
        } else {
            targetIndices.zipWithNext().count { (previous, next) -> next >= previous }.toDouble() /
                (targetIndices.size - 1)
        }
        val tailConsistency = if (targetIndices.isEmpty()) {
            1.0
        } else {
            (targetIndices.last() + 1).toDouble() / (targetIndices.maxOrNull()!! + 1)
        }
        return TocCandidate(
            items = validItems,
            score = validity * 0.55 + monotonicity * 0.30 + tailConsistency * 0.15,
            sourcePriority = sourcePriority,
        )
    }

    private fun tocTargetExists(
        zip: ZipFile,
        href: String,
        documentCache: MutableMap<String, Document?>,
    ): Boolean {
        val entryPath = href.substringBefore('#')
        val entry = zip.getEntry(entryPath) ?: return false
        if (entry.isDirectory) {
            return false
        }
        val rawFragment = href.substringAfter('#', "")
        if (rawFragment.isBlank()) {
            return true
        }
        val document = documentCache.getOrPut(entryPath) {
            runCatching { readXml(zip, entryPath) }.getOrNull()
        } ?: return true
        val fragment = runCatching { URLDecoder.decode(rawFragment, StandardCharsets.UTF_8) }
            .getOrDefault(rawFragment)
        val elements = document.getElementsByTagNameNS("*", "*")
        for (index in 0 until elements.length) {
            val element = elements.item(index) as? Element ?: continue
            if (element.getAttribute("id") == fragment || element.getAttribute("name") == fragment) {
                return true
            }
        }
        return false
    }

    private fun deduplicateTocItems(items: List<ManifestTocItem>): List<ManifestTocItem> =
        items.distinctBy { item -> item.title.normalizeWhitespace().lowercase() to item.href }

    private fun isExternalReference(href: String): Boolean {
        val normalized = href.trim().lowercase()
        return normalized.startsWith("http://") ||
            normalized.startsWith("https://") ||
            normalized.startsWith("mailto:") ||
            normalized.startsWith("javascript:")
    }

    private fun extractIndexText(
        zip: ZipFile,
        manifestItems: Map<String, EpubManifestItem>,
        spineHrefs: List<String>,
    ): String {
        val candidates = if (spineHrefs.isNotEmpty()) {
            spineHrefs
        } else {
            manifestItems.values
                .filter { it.mediaType.contains("html", ignoreCase = true) || it.fullPath.endsWith(".xhtml", ignoreCase = true) }
                .map { it.fullPath }
        }

        val text = buildString {
            for (href in candidates.take(8)) {
                val entryPath = href.substringBefore('#')
                if (entryPath.isBlank()) {
                    continue
                }
                val entry = zip.getEntry(entryPath) ?: continue
                append(extractTextFromEntry(zip, entry))
                append('\n')
                if (length >= 40_000) {
                    break
                }
            }
        }

        return text.normalizeWhitespace().take(40_000)
    }

    private fun extractTextFromEntry(zip: ZipFile, entry: ZipEntry): String {
        return try {
            val document = zip.getInputStream(entry).use { input ->
                parseXml(input.readBytes())
            }
            document.documentElement?.textContent.normalizeWhitespace()
        } catch (_: Exception) {
            zip.getInputStream(entry).use { input ->
                String(input.readBytes(), StandardCharsets.UTF_8)
                    .replace(Regex("<[^>]+>"), " ")
                    .normalizeWhitespace()
            }
        }
    }

    private fun extractStructuredBlocks(
        document: Document,
        chapterIndex: Int,
        chapterPath: String,
        imageItemsByPath: Map<String, EpubManifestItem>,
    ): List<StructuredBookBlock> {
        val body = document.getElementsByTagNameNS("*", "body").item(0) as? Element
        val root = body ?: document.documentElement ?: return emptyList()
        val pendingBlocks = mutableListOf<PendingBlock>()
        root.childNodes.asSequence().forEach { node ->
            collectBlocks(
                node = node,
                blocks = pendingBlocks,
                chapterPath = chapterPath,
                imageItemsByPath = imageItemsByPath,
            )
        }
        return pendingBlocks.mapIndexedNotNull { index, block ->
            when (block.type) {
                StructuredBlockType.DIVIDER -> StructuredBookBlock(
                    type = StructuredBlockType.DIVIDER,
                    anchor = blockAnchor(chapterIndex, index + 1),
                    text = "",
                    plainText = "",
                    meta = block.meta,
                )

                else -> {
                    val text = block.text.normalizeWhitespace()
                    if (text.isBlank() && block.type != StructuredBlockType.IMAGE) {
                        null
                    } else {
                        StructuredBookBlock(
                            type = block.type,
                            anchor = blockAnchor(chapterIndex, index + 1),
                            text = text,
                            plainText = text,
                            meta = block.meta,
                        )
                    }
                }
            }
        }
    }

    private fun collectBlocks(
        node: Node,
        blocks: MutableList<PendingBlock>,
        chapterPath: String,
        imageItemsByPath: Map<String, EpubManifestItem>,
    ) {
        if (node.nodeType != Node.ELEMENT_NODE) {
            return
        }
        val element = node as Element
        when (element.localName?.lowercase()) {
            "h1", "h2", "h3", "h4", "h5", "h6" -> {
                val text = element.textContent.normalizeWhitespace()
                if (text.isNotBlank()) {
                    blocks += PendingBlock(
                        type = StructuredBlockType.HEADING,
                        text = text,
                        meta = mapOf("level" to element.localName.removePrefix("h").toInt()),
                    )
                }
            }

            "p", "li" -> {
                collectInlineBlocks(
                    element = element,
                    blocks = blocks,
                    textBlockType = if (isHeadingLike(element)) {
                        StructuredBlockType.HEADING
                    } else {
                        StructuredBlockType.PARAGRAPH
                    },
                    chapterPath = chapterPath,
                    imageItemsByPath = imageItemsByPath,
                )
            }

            "blockquote" -> {
                collectInlineBlocks(
                    element = element,
                    blocks = blocks,
                    textBlockType = StructuredBlockType.QUOTE,
                    chapterPath = chapterPath,
                    imageItemsByPath = imageItemsByPath,
                )
            }

            "figure" -> collectFigureBlock(
                element = element,
                blocks = blocks,
                chapterPath = chapterPath,
                imageItemsByPath = imageItemsByPath,
            )

            "img", "image" -> imageBlockFromElement(
                element = element,
                chapterPath = chapterPath,
                imageItemsByPath = imageItemsByPath,
                caption = null,
            )?.let { blocks += it }

            "hr" -> blocks += PendingBlock(type = StructuredBlockType.DIVIDER, text = "")

            "script", "style", "head", "nav" -> return

            else -> element.childNodes.asSequence().forEach { child ->
                collectBlocks(
                    node = child,
                    blocks = blocks,
                    chapterPath = chapterPath,
                    imageItemsByPath = imageItemsByPath,
                )
            }
        }
    }

    private fun isHeadingLike(element: Element): Boolean {
        if (element.getAttribute("role").equals("heading", ignoreCase = true)) {
            return true
        }
        val epubType = element.getAttribute("epub:type")
            .ifBlank { element.getAttributeNS("http://www.idpf.org/2007/ops", "type") }
            .lowercase()
            .split(Regex("\\s+"))
        if (epubType.any { it in HEADING_EPUB_TYPES }) {
            return true
        }
        return element.getAttribute("class")
            .split(Regex("\\s+"))
            .filter { it.isNotBlank() }
            .any { className -> HEADING_CLASS_PATTERN.matches(className) }
    }

    private fun collectInlineBlocks(
        element: Element,
        blocks: MutableList<PendingBlock>,
        textBlockType: StructuredBlockType,
        chapterPath: String,
        imageItemsByPath: Map<String, EpubManifestItem>,
    ) {
        val textBuffer = StringBuilder()

        fun appendVisibleText(node: Node) {
            when (node.nodeType) {
                Node.TEXT_NODE, Node.CDATA_SECTION_NODE -> textBuffer.append(node.textContent)
                Node.ELEMENT_NODE -> {
                    val childElement = node as Element
                    when (childElement.localName?.lowercase()) {
                        "script", "style", "head", "nav", "img", "image", "figure" -> return
                        "br" -> textBuffer.append('\n')
                        else -> childElement.childNodes.asSequence().forEach(::appendVisibleText)
                    }
                }
            }
        }

        fun flushText() {
            val text = textBuffer.toString().normalizeWhitespace()
            textBuffer.clear()
            if (text.isNotBlank()) {
                blocks += PendingBlock(type = textBlockType, text = text)
            }
        }

        element.childNodes.asSequence().forEach { child ->
            if (child.nodeType == Node.ELEMENT_NODE) {
                val childElement = child as Element
                when (childElement.localName?.lowercase()) {
                    "img", "image" -> {
                        flushText()
                        imageBlockFromElement(
                            element = childElement,
                            chapterPath = chapterPath,
                            imageItemsByPath = imageItemsByPath,
                            caption = null,
                        )?.let { blocks += it }
                        return@forEach
                    }

                    "figure" -> {
                        flushText()
                        collectFigureBlock(
                            element = childElement,
                            blocks = blocks,
                            chapterPath = chapterPath,
                            imageItemsByPath = imageItemsByPath,
                        )
                        return@forEach
                    }
                }
            }
            appendVisibleText(child)
        }

        flushText()
    }

    private fun collectFigureBlock(
        element: Element,
        blocks: MutableList<PendingBlock>,
        chapterPath: String,
        imageItemsByPath: Map<String, EpubManifestItem>,
    ) {
        val caption = element.getElementsByTagNameNS("*", "figcaption")
            .item(0)
            ?.textContent
            .normalizeWhitespace()
        val images = element.getElementsByTagNameNS("*", "img").asSequence()
            .mapNotNull { it as? Element }
            .toList()
            .ifEmpty {
                element.getElementsByTagNameNS("*", "image").asSequence()
                    .mapNotNull { it as? Element }
                    .toList()
            }

        if (images.isEmpty()) {
            caption?.takeIf { it.isNotBlank() }?.let {
                blocks += PendingBlock(type = StructuredBlockType.PARAGRAPH, text = it)
            }
            return
        }

        images.forEachIndexed { index, image ->
            imageBlockFromElement(
                element = image,
                chapterPath = chapterPath,
                imageItemsByPath = imageItemsByPath,
                caption = caption.takeIf { index == 0 },
            )?.let { blocks += it }
        }
    }

    private fun imageBlockFromElement(
        element: Element,
        chapterPath: String,
        imageItemsByPath: Map<String, EpubManifestItem>,
        caption: String?,
    ): PendingBlock? {
        val rawSrc = element.getAttribute("src")
            .ifBlank { element.getAttribute("href") }
            .ifBlank { element.getAttribute("xlink:href") }
            .ifBlank { element.getAttributeNS("http://www.w3.org/1999/xlink", "href") }
            .trim()
        if (rawSrc.isBlank()) {
            return null
        }
        val resolvedPath = resolveHref(chapterPath, rawSrc).substringBefore('#')
        val imageItem = imageItemsByPath[resolvedPath]
        if (imageItem == null) {
            val fallbackText = caption.normalizeWhitespace().takeIf { it.isNotBlank() }
                ?: element.getAttribute("alt").normalizeWhitespace().takeIf { it.isNotBlank() }
                ?: "Unsupported image"
            return PendingBlock(
                type = StructuredBlockType.PARAGRAPH,
                text = fallbackText,
                meta = mapOf(
                    "unsupportedImage" to true,
                    "src" to resolvedPath,
                ),
            )
        }

        val alt = element.getAttribute("alt").normalizeWhitespace().takeIf { it.isNotBlank() }
        val normalizedCaption = caption.normalizeWhitespace().takeIf { it.isNotBlank() }
        val displayText = normalizedCaption ?: alt ?: ""
        val meta = linkedMapOf<String, Any?>(
            "resourceId" to encodeResourceId(imageItem.fullPath),
            "mediaType" to imageItem.mediaType,
            "src" to imageItem.fullPath,
        )
        alt?.let { meta["alt"] = it }
        normalizedCaption?.let { meta["caption"] = it }
        parseDimension(element.getAttribute("width"))?.let { meta["width"] = it }
        parseDimension(element.getAttribute("height"))?.let { meta["height"] = it }

        return PendingBlock(
            type = StructuredBlockType.IMAGE,
            text = displayText,
            meta = meta,
        )
    }

    private fun resolveEntryPath(baseDir: String, relativePath: String): String {
        val path = relativePath.substringBefore('#')
        if (path.isBlank()) {
            return baseDir
        }
        val base = if (baseDir.isBlank()) "" else "$baseDir/"
        return Path.of(base + path).normalize().toString().replace('\\', '/')
    }

    private fun resolveHref(baseFilePath: String, href: String): String {
        val path = href.substringBefore('#')
        val fragment = href.substringAfter('#', "")
        val baseDir = baseFilePath.substringBeforeLast('/', "")
        val resolvedPath = if (path.isBlank()) {
            baseFilePath
        } else {
            resolveEntryPath(baseDir, path)
        }
        return if (fragment.isBlank()) resolvedPath else "$resolvedPath#$fragment"
    }

    private fun inferMimeTypeFromPath(path: String): String = when (path.substringAfterLast('.', "").lowercase()) {
        "jpg", "jpeg" -> "image/jpeg"
        "png" -> "image/png"
        "webp" -> "image/webp"
        "gif" -> "image/gif"
        "svg" -> "image/svg+xml"
        else -> "application/octet-stream"
    }

    private fun encodeResourceId(path: String): String =
        Base64.getUrlEncoder()
            .withoutPadding()
            .encodeToString(path.toByteArray(StandardCharsets.UTF_8))

    private fun decodeResourceId(resourceId: String): String? =
        try {
            String(Base64.getUrlDecoder().decode(resourceId), StandardCharsets.UTF_8)
                .replace('\\', '/')
                .takeIf { it.isNotBlank() && !it.startsWith("/") && ".." !in it.split('/') }
        } catch (_: IllegalArgumentException) {
            null
        }

    private fun parseDimension(value: String): Int? =
        value.trim()
            .removeSuffix("px")
            .substringBefore('.')
            .toIntOrNull()
            ?.takeIf { it > 0 }

    private fun readXml(zip: ZipFile, entryPath: String): Document {
        val entry = zip.getEntry(entryPath)
            ?: throw IllegalArgumentException("EPUB archive is missing $entryPath")
        val bytes = zip.getInputStream(entry).use { it.readBytes() }
        return parseXml(bytes)
    }

    private fun parseXml(bytes: ByteArray): Document {
        val factory = DocumentBuilderFactory.newInstance()
        factory.isNamespaceAware = true
        factory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true)
        // EPUB 2 NCX documents commonly declare the standard DAISY DTD. Allow the
        // declaration itself, but never load external DTDs or resolve entities.
        factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", false)
        factory.setFeature("http://xml.org/sax/features/external-general-entities", false)
        factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false)
        factory.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false)
        factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "")
        factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "")
        factory.isXIncludeAware = false
        factory.isExpandEntityReferences = false
        val builder = factory.newDocumentBuilder()
        return ByteArrayInputStream(bytes).use(builder::parse)
    }

    private fun firstText(document: Document, localName: String): String? {
        val nodes = document.getElementsByTagNameNS("*", localName)
        for (index in 0 until nodes.length) {
            val text = nodes.item(index)?.textContent.normalizeWhitespace()
            if (!text.isNullOrBlank()) {
                return text
            }
        }
        return null
    }

    private fun String?.normalizeWhitespace(): String = this
        .orEmpty()
        .replace('\u00a0', ' ')
        .replace(Regex("\\s+"), " ")
        .trim()

    private fun NodeList.asSequence(): Sequence<Node> = sequence {
        for (index in 0 until length) {
            yield(item(index))
        }
    }

    private fun chapterAnchor(chapterIndex: Int): String = "chapter-$chapterIndex"

    private fun blockAnchor(chapterIndex: Int, blockIndex: Int): String = "chapter-$chapterIndex-block-$blockIndex"

    private data class ParsedEpub(
        val metadata: BookMetadata,
        val manifest: ReadingManifest,
        val indexExcerpt: String,
    )

    private data class TocCandidate(
        val items: List<ManifestTocItem>,
        val score: Double,
        val sourcePriority: Int,
    )

    private data class EpubManifestItem(
        val id: String,
        val href: String,
        val fullPath: String,
        val mediaType: String,
        val properties: Set<String>,
    )

    private data class CoverArchiveItem(
        val path: String,
        val mediaType: String,
    )

    private data class PendingBlock(
        val type: StructuredBlockType,
        val text: String,
        val meta: Map<String, Any?> = emptyMap(),
    )

    private companion object {
        private const val STRUCTURED_CONTENT_MODEL_V2 = "UNIFIED_V2"
        private const val TOC_PRIORITY_GUIDE = 1
        private const val TOC_PRIORITY_NCX = 2
        private const val TOC_PRIORITY_EPUB3_NAV = 3
        private val HEADING_EPUB_TYPES = setOf(
            "chapter",
            "part",
            "section",
            "subtitle",
            "title",
        )
        private val HEADING_CLASS_PATTERN = Regex(
            "(?:book[-_]?)?(?:title|heading|headline|subtitle)\\d*|" +
                "(?:chapter|section)(?:[-_]?(?:title|heading))?\\d*",
            RegexOption.IGNORE_CASE,
        )
        private val PNG_SIGNATURE = byteArrayOf(
            0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        )
        private val SUPPORTED_IMAGE_MEDIA_TYPES = setOf(
            "image/jpeg",
            "image/png",
            "image/webp",
            "image/gif",
        )
    }
}
