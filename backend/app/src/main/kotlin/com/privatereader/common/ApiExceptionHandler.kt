package com.privatereader.common

import org.springframework.http.HttpStatus
import org.springframework.security.access.AccessDeniedException
import org.springframework.web.bind.MethodArgumentNotValidException
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestControllerAdvice

@RestControllerAdvice
class ApiExceptionHandler {
    @ExceptionHandler(IllegalArgumentException::class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    fun handleIllegalArgument(exception: IllegalArgumentException): Map<String, Any> =
        mapOf("error" to (exception.message ?: "Bad request"))

    @ExceptionHandler(AccessDeniedException::class)
    @ResponseStatus(HttpStatus.FORBIDDEN)
    fun handleAccessDenied(exception: AccessDeniedException): Map<String, Any> =
        mapOf("error" to (exception.message ?: "Forbidden"))

    @ExceptionHandler(MethodArgumentNotValidException::class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    fun handleValidation(exception: MethodArgumentNotValidException): Map<String, Any> =
        mapOf(
            "error" to "Validation failed",
            "details" to exception.bindingResult.fieldErrors.associate { it.field to (it.defaultMessage ?: "invalid") },
        )
}

