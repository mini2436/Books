package com.privatereader.auth

import jakarta.validation.Valid
import org.springframework.http.CacheControl
import org.springframework.http.MediaType
import org.springframework.http.ResponseEntity
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PatchMapping
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestPart
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.multipart.MultipartFile

@RestController
@RequestMapping("/api/me/profile")
class ProfileController(
    private val authRepository: AuthRepository,
) {
    @GetMapping
    fun getProfile(@AuthenticationPrincipal principal: UserPrincipal): AuthUserView =
        requireNotNull(authRepository.findUserById(principal.id)) { "User not found" }.toAuthUserView()

    @PatchMapping
    fun updateProfile(
        @AuthenticationPrincipal principal: UserPrincipal,
        @Valid @RequestBody request: UpdateProfileRequest,
    ): AuthUserView {
        val displayName = request.displayName?.trim()?.takeIf { it.isNotEmpty() }
        return authRepository.updateDisplayName(principal.id, displayName).toAuthUserView()
    }

    @PostMapping("/avatar", consumes = [MediaType.MULTIPART_FORM_DATA_VALUE])
    fun uploadAvatar(
        @AuthenticationPrincipal principal: UserPrincipal,
        @RequestPart("file") file: MultipartFile,
    ): AuthUserView {
        require(!file.isEmpty) { "Avatar file is empty" }
        require(file.size <= MAX_AVATAR_SIZE) { "Avatar file must not exceed 5 MB" }
        val contentType = file.contentType?.lowercase() ?: MediaType.APPLICATION_OCTET_STREAM_VALUE
        require(contentType in SUPPORTED_AVATAR_TYPES) { "Only JPEG, PNG, WebP or GIF avatars are supported" }
        return authRepository.updateAvatar(principal.id, file.bytes, contentType).toAuthUserView()
    }

    @GetMapping("/avatar")
    fun getAvatar(@AuthenticationPrincipal principal: UserPrincipal): ResponseEntity<ByteArray> {
        val avatar = authRepository.findAvatar(principal.id)
            ?: return ResponseEntity.notFound().build()
        return ResponseEntity.ok()
            .cacheControl(CacheControl.noCache())
            .contentType(MediaType.parseMediaType(avatar.contentType))
            .body(avatar.bytes)
    }

    private companion object {
        const val MAX_AVATAR_SIZE = 5L * 1024L * 1024L
        val SUPPORTED_AVATAR_TYPES = setOf(
            MediaType.IMAGE_JPEG_VALUE,
            MediaType.IMAGE_PNG_VALUE,
            "image/webp",
            MediaType.IMAGE_GIF_VALUE,
        )
    }
}
