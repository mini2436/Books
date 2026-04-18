package com.privatereader.plugin

enum class PluginCapability {
    READ_ONLINE,
    EXTRACT_TOC,
    EXTRACT_COVER,
    FULL_TEXT_INDEX,
    SUPPORTS_ANNOTATIONS,
}

data class BookMetadata(
    val title: String,
    val author: String? = null,
    val language: String? = null,
    val description: String? = null,
    val tags: List<String> = emptyList(),
)

data class CoverExtractionResult(
    val mimeType: String,
    val bytes: ByteArray,
)

data class ReadingManifest(
    val format: String,
    val toc: List<ManifestTocItem>,
    val primaryLocation: String,
)

data class ManifestTocItem(
    val title: String,
    val href: String,
)

data class IndexableContent(
    val text: String,
)

