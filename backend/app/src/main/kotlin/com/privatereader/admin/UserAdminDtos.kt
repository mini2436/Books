package com.privatereader.admin

import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size

data class ResetUserPasswordRequest(
    @field:Size(min = 6, max = 128)
    val newPassword: String,
)

data class DeleteAdministratorRequest(
    @field:NotBlank
    @field:Size(max = 128)
    val targetPassword: String,
)
