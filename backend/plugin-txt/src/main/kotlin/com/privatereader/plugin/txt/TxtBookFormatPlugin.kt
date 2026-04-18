package com.privatereader.plugin.txt

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
}
