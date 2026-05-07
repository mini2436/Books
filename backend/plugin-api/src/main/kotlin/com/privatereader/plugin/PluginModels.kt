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

data class BookResource(
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

data class StructuredBookContent(
    val chapters: List<StructuredBookChapter>,
    val contentModel: String = "UNIFIED_V1",
)

data class StructuredBookChapter(
    val title: String,
    val anchor: String,
    val blocks: List<StructuredBookBlock>,
)

data class StructuredBookBlock(
    val type: StructuredBlockType,
    val anchor: String,
    val text: String,
    val plainText: String,
    val meta: Map<String, Any?> = emptyMap(),
)

enum class StructuredBlockType(
    val storageName: String,
) {
    HEADING("heading"),
    PARAGRAPH("paragraph"),
    QUOTE("quote"),
    DIVIDER("divider"),
    IMAGE("image"),
    ;

    companion object {
        fun fromStorageName(value: String): StructuredBlockType =
            entries.firstOrNull { it.storageName == value.lowercase() }
                ?: throw IllegalArgumentException("Unsupported structured block type: $value")
    }
}
