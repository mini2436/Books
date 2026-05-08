package com.privatereader.plugin.pdf

import com.privatereader.plugin.BookFormatPlugin
import com.privatereader.plugin.BookMetadata
import com.privatereader.plugin.IndexableContent
import com.privatereader.plugin.ManifestTocItem
import com.privatereader.plugin.PluginCapability
import com.privatereader.plugin.ReadingManifest
import org.apache.pdfbox.Loader
import org.apache.pdfbox.text.PDFTextStripper
import org.springframework.stereotype.Component
import java.nio.file.Path

@Component
class PdfBookFormatPlugin : BookFormatPlugin {
    override val pluginId: String = "plugin-pdf"
    override val displayName: String = "PDF Plugin"
    override val supportedExtensions: Set<String> = setOf("pdf")
    override val capabilities: Set<PluginCapability> = setOf(
        PluginCapability.READ_ONLINE,
        PluginCapability.FULL_TEXT_INDEX,
        PluginCapability.SUPPORTS_ANNOTATIONS,
    )

    override fun canHandle(file: Path): Boolean = file.fileName.toString().endsWith(".pdf", ignoreCase = true)

    override fun extractMetadata(file: Path): BookMetadata = BookMetadata(
        title = readPdf(file) { document ->
            document.documentInformation.title
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
        } ?: file.fileName.toString().removeSuffix(".pdf").replace('_', ' '),
        author = readPdf(file) { document ->
            document.documentInformation.author
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
        } ?: "Unknown Author",
        description = "Imported PDF file.",
        tags = listOf("pdf"),
    )

    override fun buildManifest(file: Path): ReadingManifest = ReadingManifest(
        format = "pdf",
        toc = readPdf(file) { document ->
            val pageCount = document.numberOfPages.coerceAtLeast(1)
            (1..pageCount).map { pageNumber ->
                ManifestTocItem(title = "Page $pageNumber", href = "#page=$pageNumber")
            }
        } ?: listOf(ManifestTocItem(title = "Page 1", href = "#page=1")),
        primaryLocation = "#page=1",
        meta = mapOf(
            "pageCount" to (readPdf(file) { document -> document.numberOfPages } ?: 1),
        ),
    )

    override fun extractIndexableContent(file: Path): IndexableContent = IndexableContent(
        text = readPdf(file) { document ->
            PDFTextStripper().getText(document).trim()
        }?.takeIf { it.isNotEmpty() } ?: "PDF content indexing placeholder for ${file.fileName}",
    )

    private fun <T> readPdf(file: Path, block: (org.apache.pdfbox.pdmodel.PDDocument) -> T): T? =
        runCatching {
            Loader.loadPDF(file.toFile()).use(block)
        }.getOrNull()
}

