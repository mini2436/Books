package com.privatereader.plugin

import java.nio.file.Path

interface BookFormatPlugin {
    val pluginId: String
    val displayName: String
    val supportedExtensions: Set<String>
    val capabilities: Set<PluginCapability>

    fun canHandle(file: Path): Boolean

    fun extractMetadata(file: Path): BookMetadata

    fun extractCover(file: Path): CoverExtractionResult? = null

    fun buildManifest(file: Path): ReadingManifest? = null

    fun extractIndexableContent(file: Path): IndexableContent? = null

    fun extractStructuredContent(file: Path): StructuredBookContent? = null
}
