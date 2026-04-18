package com.privatereader.bootstrap

import com.privatereader.auth.TokenService
import org.springframework.boot.ApplicationArguments
import org.springframework.boot.ApplicationRunner
import org.springframework.stereotype.Component

@Component
class BootstrapAdminRunner(
    private val tokenService: TokenService,
) : ApplicationRunner {
    override fun run(args: ApplicationArguments?) {
        tokenService.bootstrapAdminIfNeeded()
    }
}

