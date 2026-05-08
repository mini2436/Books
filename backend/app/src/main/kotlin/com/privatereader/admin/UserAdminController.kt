package com.privatereader.admin

import com.privatereader.auth.RoleExpressions
import com.privatereader.books.CreateUserRequest
import com.privatereader.books.UpdateUserRequest
import com.privatereader.books.UserView
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
@RequestMapping("/api/admin/users")
class UserAdminController(
    private val userAdminService: UserAdminService,
) {
    @GetMapping
    @PreAuthorize(RoleExpressions.SUPER_ADMIN_ONLY)
    fun listUsers(): List<UserView> = userAdminService.listUsers()

    @PostMapping
    @PreAuthorize(RoleExpressions.SUPER_ADMIN_ONLY)
    fun createUser(@Valid @RequestBody request: CreateUserRequest): UserView = userAdminService.createUser(request)

    @PatchMapping("/{userId}")
    @PreAuthorize(RoleExpressions.SUPER_ADMIN_ONLY)
    fun updateUser(
        @PathVariable userId: Long,
        @RequestBody request: UpdateUserRequest,
    ): UserView = userAdminService.updateUser(userId, request)
}

