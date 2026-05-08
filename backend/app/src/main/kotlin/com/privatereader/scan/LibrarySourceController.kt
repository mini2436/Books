package com.privatereader.scan

import com.privatereader.auth.RoleExpressions
import com.privatereader.books.CreateLibrarySourceRequest
import com.privatereader.books.LibrarySourceView
import com.privatereader.books.UpdateLibrarySourceRequest
import jakarta.validation.Valid
import org.springframework.security.access.prepost.PreAuthorize
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PatchMapping
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
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun listSources(): List<LibrarySourceView> = librarySourceService.listSources()

    @PostMapping
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun createSource(@Valid @RequestBody request: CreateLibrarySourceRequest): LibrarySourceView =
        librarySourceService.createSource(request)

    @PatchMapping("/{sourceId}")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun updateSource(
        @PathVariable sourceId: Long,
        @Valid @RequestBody request: UpdateLibrarySourceRequest,
    ): LibrarySourceView = librarySourceService.updateSource(sourceId, request)

    @PostMapping("/{sourceId}/rescan")
    @PreAuthorize(RoleExpressions.ADMIN_ACCESS)
    fun rescan(@PathVariable sourceId: Long): Map<String, Any> = librarySourceService.scanSource(sourceId)
}
