package com.privatereader.plugin

import com.privatereader.plugin.epub.EpubBookFormatPlugin
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class EpubBookFormatPluginTest {
    private val plugin = EpubBookFormatPlugin()

    @Test
    fun `extracts structured chapters from epub spine`() {
        val tempFile = Files.createTempFile("reader-epub", ".epub")
        ZipOutputStream(Files.newOutputStream(tempFile)).use { zip ->
            writeEntry(zip, "mimetype", "application/epub+zip")
            writeEntry(
                zip,
                "META-INF/container.xml",
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                  <rootfiles>
                    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
                  </rootfiles>
                </container>
                """.trimIndent(),
            )
            writeEntry(
                zip,
                "OEBPS/content.opf",
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
                  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                    <dc:title>Sample EPUB</dc:title>
                  </metadata>
                  <manifest>
                    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                    <item id="chap1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
                    <item id="chap2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
                  </manifest>
                  <spine>
                    <itemref idref="chap1"/>
                    <itemref idref="chap2"/>
                  </spine>
                </package>
                """.trimIndent(),
            )
            writeEntry(
                zip,
                "OEBPS/nav.xhtml",
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
                  <body>
                    <nav epub:type="toc">
                      <ol>
                        <li><a href="chapter1.xhtml">Intro</a></li>
                        <li><a href="chapter2.xhtml">Next</a></li>
                      </ol>
                    </nav>
                  </body>
                </html>
                """.trimIndent(),
            )
            writeEntry(
                zip,
                "OEBPS/chapter1.xhtml",
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <html xmlns="http://www.w3.org/1999/xhtml">
                  <body>
                    <h1>Intro</h1>
                    <p>First chapter paragraph.</p>
                  </body>
                </html>
                """.trimIndent(),
            )
            writeEntry(
                zip,
                "OEBPS/chapter2.xhtml",
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <html xmlns="http://www.w3.org/1999/xhtml">
                  <body>
                    <h2>Next</h2>
                    <blockquote>Quoted text.</blockquote>
                  </body>
                </html>
                """.trimIndent(),
            )
        }

        val content = plugin.extractStructuredContent(tempFile)

        assertEquals(2, content?.chapters?.size)
        assertEquals("Intro", content?.chapters?.get(0)?.title)
        assertEquals(1, content?.chapters?.get(0)?.blocks?.size)
        assertEquals("paragraph", content?.chapters?.get(0)?.blocks?.first()?.type?.storageName)
        assertEquals("quote", content?.chapters?.get(1)?.blocks?.first()?.type?.storageName)
        assertTrue(content?.chapters?.get(1)?.blocks?.first()?.anchor?.startsWith("chapter-1-block-") == true)
    }

    private fun writeEntry(zip: ZipOutputStream, name: String, content: String) {
        zip.putNextEntry(ZipEntry(name))
        zip.write(content.toByteArray(StandardCharsets.UTF_8))
        zip.closeEntry()
    }
}
