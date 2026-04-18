package com.privatereader.plugin.epub

import com.privatereader.plugin.BookFormatPlugin
import com.privatereader.plugin.BookMetadata
import com.privatereader.plugin.IndexableContent
import com.privatereader.plugin.ManifestTocItem
import com.privatereader.plugin.PluginCapability
import com.privatereader.plugin.ReadingManifest
import org.springframework.stereotype.Component
import java.nio.file.Files
import java.nio.file.Path

@Component
class EpubBookFormatPlugin : BookFormatPlugin {
    override val pluginId: String = "plugin-epub"
    override val displayName: String = "EPUB Plugin"
    override val supportedExtensions: Set<String> = setOf("epub")
    override val capabilities: Set<PluginCapability> = setOf(
        PluginCapability.READ_ONLINE,
        PluginCapability.EXTRACT_TOC,
        PluginCapability.FULL_TEXT_INDEX,
        PluginCapability.SUPPORTS_ANNOTATIONS,
    )

    override fun canHandle(file: Path): Boolean = file.fileName.toString().endsWith(".epub", ignoreCase = true)

    override fun extractMetadata(file: Path): BookMetadata {
        val base = file.fileName.toString().removeSuffix(".epub")
        return BookMetadata(
            title = base.replace('_', ' '),
            author = "Unknown Author",
            language = "en",
            description = "Imported EPUB file.",
            tags = listOf("epub"),
        )
    }

    override fun buildManifest(file: Path): ReadingManifest = ReadingManifest(
        format = "epub",
        toc = listOf(
            ManifestTocItem(title = "Start", href = "epubcfi(/6/2[start]!/4/1:0)"),
        ),
        primaryLocation = "epubcfi(/6/2[start]!/4/1:0)",
    )

    override fun extractIndexableContent(file: Path): IndexableContent? {
        val snippet = Files.newInputStream(file).use { input ->
            input.readNBytes(2048).decodeToString()
        }
        return IndexableContent(text = snippet)
    }
}

