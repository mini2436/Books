package com.privatereader.plugin

import com.privatereader.plugin.epub.EpubBookFormatPlugin
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.util.Base64
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class EpubBookFormatPluginTest {
    private val plugin = EpubBookFormatPlugin()

    @Test
    fun `extracts toc from epub 2 ncx with standard doctype`() {
        val tempFile = Files.createTempFile("reader-epub2-ncx", ".epub")
        ZipOutputStream(Files.newOutputStream(tempFile)).use { zip ->
            writeEntry(zip, "mimetype", "application/epub+zip")
            writeEntry(
                zip,
                "META-INF/container.xml",
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                  <rootfiles>
                    <rootfile full-path="OPS/content.opf" media-type="application/oebps-package+xml"/>
                  </rootfiles>
                </container>
                """.trimIndent(),
            )
            writeEntry(
                zip,
                "OPS/content.opf",
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
                  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                    <dc:title>EPUB 2 Sample</dc:title>
                  </metadata>
                  <manifest>
                    <item id="ncx" href="fb.ncx" media-type="application/x-dtbncx+xml"/>
                    <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
                  </manifest>
                  <spine toc="ncx"><itemref idref="chapter"/></spine>
                </package>
                """.trimIndent(),
            )
            writeEntry(
                zip,
                "OPS/fb.ncx",
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
                <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
                  <navMap>
                    <navPoint id="chapter-1"><navLabel><text>第一章</text></navLabel><content src="chapter.xhtml"/></navPoint>
                  </navMap>
                </ncx>
                """.trimIndent(),
            )
            writeEntry(
                zip,
                "OPS/chapter.xhtml",
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <html xmlns="http://www.w3.org/1999/xhtml"><body><h1>第一章</h1><p>正文</p></body></html>
                """.trimIndent(),
            )
        }

        val manifest = plugin.buildManifest(tempFile)

        assertEquals("第一章", manifest.toc.single().title)
        assertEquals("OPS/chapter.xhtml", manifest.toc.single().href)
    }

    @Test
    fun `falls back to guide toc when ncx jumps backwards and keeps first title per spine document`() {
        val tempFile = Files.createTempFile("reader-epub2-broken-ncx", ".epub")
        ZipOutputStream(Files.newOutputStream(tempFile)).use { zip ->
            writeEntry(zip, "mimetype", "application/epub+zip")
            writeEntry(
                zip,
                "META-INF/container.xml",
                """
                <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                  <rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>
                </container>
                """.trimIndent(),
            )
            writeEntry(
                zip,
                "OEBPS/content.opf",
                """
                <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
                  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Broken NCX sample</dc:title></metadata>
                  <manifest>
                    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
                    <item id="toc" href="toc.xhtml" media-type="application/xhtml+xml"/>
                    <item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>
                    <item id="two" href="two.xhtml" media-type="application/xhtml+xml"/>
                    <item id="dedication" href="dedication.xhtml" media-type="application/xhtml+xml"/>
                    <item id="afterword" href="afterword.xhtml" media-type="application/xhtml+xml"/>
                  </manifest>
                  <spine toc="ncx">
                    <itemref idref="one"/>
                    <itemref idref="two"/>
                    <itemref idref="dedication"/>
                    <itemref idref="afterword"/>
                  </spine>
                  <guide><reference type="toc" title="目录" href="toc.xhtml"/></guide>
                </package>
                """.trimIndent(),
            )
            writeEntry(
                zip,
                "OEBPS/toc.ncx",
                """
                <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
                  <navMap>
                    <navPoint id="p1"><navLabel><text>第一束信</text></navLabel><content src="one.xhtml#letter1"/></navPoint>
                    <navPoint id="p2"><navLabel><text>1．为什么写信？</text></navLabel><content src="one.xhtml#letter1"/></navPoint>
                    <navPoint id="p3"><navLabel><text>第二束信</text></navLabel><content src="two.xhtml#letter3"/></navPoint>
                    <navPoint id="p4"><navLabel><text>译后记</text></navLabel><content src="one.xhtml#note1"/></navPoint>
                  </navMap>
                </ncx>
                """.trimIndent(),
            )
            writeEntry(
                zip,
                "OEBPS/toc.xhtml",
                """
                <html xmlns="http://www.w3.org/1999/xhtml"><body>
                  <p><a href="one.xhtml#letter1">第一束信：这是些什么信？</a></p>
                  <p><a href="one.xhtml#letter1">1．为什么写信？</a></p>
                  <p><a href="two.xhtml#letter3">第二束信：爱与友谊</a></p>
                  <p><a href="afterword.xhtml">译后记</a></p>
                </body></html>
                """.trimIndent(),
            )
            writeEntry(
                zip,
                "OEBPS/one.xhtml",
                """
                <html xmlns="http://www.w3.org/1999/xhtml"><body>
                  <p class="title5">第一束信</p>
                  <p id="letter1" class="title2">1</p>
                  <p>正文</p><a id="note1">注释</a>
                </body></html>
                """.trimIndent(),
            )
            writeEntry(
                zip,
                "OEBPS/two.xhtml",
                """
                <html xmlns="http://www.w3.org/1999/xhtml"><body>
                  <p class="title5">第二束信</p><p id="letter3">3</p><p>正文</p>
                </body></html>
                """.trimIndent(),
            )
            writeEntry(
                zip,
                "OEBPS/dedication.xhtml",
                """
                <html xmlns="http://www.w3.org/1999/xhtml"><body>
                  <p class="title1">献给莉莉</p>
                </body></html>
                """.trimIndent(),
            )
            writeEntry(
                zip,
                "OEBPS/afterword.xhtml",
                """
                <html xmlns="http://www.w3.org/1999/xhtml"><body>
                  <p class="title1">译后记</p><p>后记正文</p>
                </body></html>
                """.trimIndent(),
            )
        }

        val manifest = plugin.buildManifest(tempFile)
        val content = plugin.extractStructuredContent(tempFile)

        assertEquals(
            listOf("第一束信：这是些什么信？", "1．为什么写信？", "第二束信：爱与友谊", "译后记"),
            manifest.toc.map { it.title },
        )
        assertEquals(
            listOf("第一束信：这是些什么信？", "第二束信：爱与友谊", "献给莉莉", "译后记"),
            content.chapters.map { it.title },
        )
        assertEquals("heading", content.chapters[0].blocks.first().type.storageName)
    }

    @Test
    fun `extracts conventional cover omitted from epub manifest`() {
        val tempFile = Files.createTempFile("reader-epub-unlisted-cover", ".epub")
        val coverBytes = byteArrayOf(0x01, 0x02, 0x03)
        ZipOutputStream(Files.newOutputStream(tempFile)).use { zip ->
            writeEntry(
                zip,
                "META-INF/container.xml",
                """
                <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                  <rootfiles><rootfile full-path="OPS/content.opf"/></rootfiles>
                </container>
                """.trimIndent(),
            )
            writeEntry(
                zip,
                "OPS/content.opf",
                """
                <package xmlns="http://www.idpf.org/2007/opf">
                  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Cover fallback</dc:title></metadata>
                  <manifest/>
                </package>
                """.trimIndent(),
            )
            writeBytes(zip, "OPS/images/cover.jpg", coverBytes)
        }

        val cover = plugin.extractCover(tempFile)

        assertNotNull(cover)
        assertEquals("image/jpeg", cover?.mimeType)
        assertArrayEquals(coverBytes, cover?.bytes)
    }

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

    @Test
    fun `extracts image blocks and resources from epub spine`() {
        val tempFile = Files.createTempFile("reader-epub-images", ".epub")
        val imageBytes = byteArrayOf(0x01, 0x02, 0x03, 0x04)
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
                    <dc:title>Image EPUB</dc:title>
                  </metadata>
                  <manifest>
                    <item id="chap1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
                    <item id="pic" href="images/pic.png" media-type="image/png"/>
                    <item id="photo" href="images/photo.jpg" media-type="image/jpeg"/>
                  </manifest>
                  <spine>
                    <itemref idref="chap1"/>
                  </spine>
                </package>
                """.trimIndent(),
            )
            writeEntry(
                zip,
                "OEBPS/chapter1.xhtml",
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <html xmlns="http://www.w3.org/1999/xhtml">
                  <body>
                    <h1>Image EPUB</h1>
                    <p>Before image <img src="images/pic.png" alt="Plate one" width="640" height="360"/> after image.</p>
                    <figure>
                      <img src="images/photo.jpg" alt="Photo alt"/>
                      <figcaption>Photo caption</figcaption>
                    </figure>
                  </body>
                </html>
                """.trimIndent(),
            )
            writeBytes(zip, "OEBPS/images/pic.png", imageBytes)
            writeBytes(zip, "OEBPS/images/photo.jpg", byteArrayOf(0x05, 0x06))
        }

        val content = plugin.extractStructuredContent(tempFile)

        assertEquals("UNIFIED_V2", content.contentModel)
        val blocks = content.chapters.first().blocks
            .filterNot { it.type.storageName == "heading" }
        assertEquals("paragraph", blocks[0].type.storageName)
        assertEquals("Before image", blocks[0].text)
        assertEquals("image", blocks[1].type.storageName)
        assertEquals("Plate one", blocks[1].text)
        assertEquals("image/png", blocks[1].meta["mediaType"])
        assertEquals(640, blocks[1].meta["width"])
        assertEquals(360, blocks[1].meta["height"])
        assertEquals("paragraph", blocks[2].type.storageName)
        assertEquals("after image.", blocks[2].text)
        assertEquals("image", blocks[3].type.storageName)
        assertEquals("Photo caption", blocks[3].text)
        assertEquals("Photo caption", blocks[3].meta["caption"])

        val resourceId = Base64.getUrlEncoder()
            .withoutPadding()
            .encodeToString("OEBPS/images/pic.png".toByteArray(StandardCharsets.UTF_8))
        val resource = plugin.extractResource(tempFile, resourceId)
        assertNotNull(resource)
        assertEquals("image/png", resource?.mimeType)
        assertArrayEquals(imageBytes, resource?.bytes)
    }

    private fun writeEntry(zip: ZipOutputStream, name: String, content: String) {
        zip.putNextEntry(ZipEntry(name))
        zip.write(content.toByteArray(StandardCharsets.UTF_8))
        zip.closeEntry()
    }

    private fun writeBytes(zip: ZipOutputStream, name: String, content: ByteArray) {
        zip.putNextEntry(ZipEntry(name))
        zip.write(content)
        zip.closeEntry()
    }
}
