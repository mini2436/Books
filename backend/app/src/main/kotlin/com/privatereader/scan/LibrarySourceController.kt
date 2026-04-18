package com.privatereader.scan

import com.privatereader.books.CreateLibrarySourceRequest
import com.privatereader.books.LibrarySourceView
import jakarta.validation.Valid
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/admin/library-sources")
class LibrarySourceController(
    private val librarySourceService: LibrarySourceService,
) {
    @GetMapping
    fun listSources(): List<LibrarySourceView> = librarySourceService.listSources()

    @PostMapping
    fun createSource(@Valid @RequestBody request: CreateLibrarySourceRequest): LibrarySourceView =
        librarySourceService.createSource(request)

    @PostMapping("/{sourceId}/rescan")
    fun rescan(@PathVariable sourceId: Long): Map<String, Any> = librarySourceService.scanSource(sourceId)
}
