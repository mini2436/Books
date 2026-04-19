package com.privatereader.plugin.txt

import com.privatereader.plugin.BookFormatPlugin
import com.privatereader.plugin.BookMetadata
import com.privatereader.plugin.IndexableContent
import com.privatereader.plugin.ManifestTocItem
import com.privatereader.plugin.PluginCapability
import com.privatereader.plugin.ReadingManifest
import com.privatereader.plugin.StructuredBlockType
import com.privatereader.plugin.StructuredBookBlock
import com.privatereader.plugin.StructuredBookChapter
import com.privatereader.plugin.StructuredBookContent
import org.springframework.stereotype.Component
import java.nio.file.Files
import java.nio.file.Path

@Component
class TxtBookFormatPlugin : BookFormatPlugin {
    override val pluginId: String = "plugin-txt"
    override val displayName: String = "TXT Plugin"
    override val supportedExtensions: Set<String> = setOf("txt")
    override val capabilities: Set<PluginCapability> = setOf(
        PluginCapability.READ_ONLINE,
        PluginCapability.FULL_TEXT_INDEX,
        PluginCapability.SUPPORTS_ANNOTATIONS,
    )

    override fun canHandle(file: Path): Boolean = file.fileName.toString().endsWith(".txt", ignoreCase = true)

    override fun extractMetadata(file: Path): BookMetadata = BookMetadata(
        title = file.fileName.toString().removeSuffix(".txt").replace('_', ' '),
        author = "Unknown Author",
        description = "Imported plain text document.",
        tags = listOf("txt"),
    )

    override fun buildManifest(file: Path): ReadingManifest = ReadingManifest(
        format = "txt",
        toc = listOf(ManifestTocItem(title = "Start", href = "offset:0")),
        primaryLocation = "offset:0",
    )

    override fun extractIndexableContent(file: Path): IndexableContent = IndexableContent(
        text = Files.readString(file).take(50_000),
    )

    override fun extractStructuredContent(file: Path): StructuredBookContent {
        val lines = Files.readAllLines(file)
        val fallbackTitle = file.fileName.toString().removeSuffix(".txt").replace('_', ' ')
        val chapters = mutableListOf<StructuredBookChapter>()
        var currentTitle = fallbackTitle
        var currentParagraphLines = mutableListOf<String>()
        var currentBlocks = mutableListOf<StructuredBookBlock>()
        var visibleBlockIndex = 1

        fun flushParagraph() {
            if (currentParagraphLines.isEmpty()) {
                return
            }
            val paragraphText = currentParagraphLines.joinToString(" ").normalizeWhitespace()
            if (paragraphText.isNotBlank()) {
                currentBlocks += StructuredBookBlock(
                    type = StructuredBlockType.PARAGRAPH,
                    anchor = blockAnchor(chapters.size, visibleBlockIndex++),
                    text = paragraphText,
                    plainText = paragraphText,
                )
            }
            currentParagraphLines = mutableListOf()
        }

        fun flushChapter() {
            flushParagraph()
            val normalizedTitle = currentTitle.normalizeWhitespace().ifBlank { "Section ${chapters.size + 1}" }
            chapters += StructuredBookChapter(
                title = normalizedTitle,
                anchor = chapterAnchor(chapters.size),
                blocks = currentBlocks.toList(),
            )
            currentBlocks = mutableListOf()
            visibleBlockIndex = 1
        }

        lines.forEachIndexed { lineIndex, rawLine ->
            val line = rawLine.trim()
            if (looksLikeChapterHeading(line) && lineIndex == 0 && chapters.isEmpty() && currentBlocks.isEmpty() && currentParagraphLines.isEmpty()) {
                currentTitle = line
                return@forEachIndexed
            }

            if (looksLikeChapterHeading(line) && (currentBlocks.isNotEmpty() || currentParagraphLines.isNotEmpty())) {
                flushChapter()
                currentTitle = line
                return@forEachIndexed
            }

            if (line.isBlank()) {
                flushParagraph()
                return@forEachIndexed
            }

            if (looksLikeDivider(line)) {
                flushParagraph()
                currentBlocks += StructuredBookBlock(
                    type = StructuredBlockType.DIVIDER,
                    anchor = blockAnchor(chapters.size, visibleBlockIndex++),
                    text = "",
                    plainText = "",
                )
                return@forEachIndexed
            }

            if (line.startsWith(">")) {
                flushParagraph()
                val quoteText = line.removePrefix(">").normalizeWhitespace()
                if (quoteText.isNotBlank()) {
                    currentBlocks += StructuredBookBlock(
                        type = StructuredBlockType.QUOTE,
                        anchor = blockAnchor(chapters.size, visibleBlockIndex++),
                        text = quoteText,
                        plainText = quoteText,
                    )
                }
                return@forEachIndexed
            }

            currentParagraphLines += line
        }

        if (currentBlocks.isNotEmpty() || currentParagraphLines.isNotEmpty() || chapters.isEmpty()) {
            flushChapter()
        }

        return StructuredBookContent(chapters = chapters)
    }

    private fun looksLikeChapterHeading(line: String): Boolean {
        if (line.isBlank() || line.length > 80) {
            return false
        }
        return line.matches(Regex("(?i)^(chapter|section|part)\\b.*")) ||
            line.matches(Regex("^第.{1,12}[章节卷部回]\\b?.*")) ||
            (line == line.uppercase() && line.length in 3..40)
    }

    private fun looksLikeDivider(line: String): Boolean = line.matches(Regex("^[-*_]{3,}$"))

    private fun chapterAnchor(chapterIndex: Int): String = "chapter-$chapterIndex"

    private fun blockAnchor(chapterIndex: Int, blockIndex: Int): String = "chapter-$chapterIndex-block-$blockIndex"

    private fun String.normalizeWhitespace(): String = replace(Regex("\\s+"), " ").trim()
}
