package com.privatereader.books

import org.slf4j.LoggerFactory
import org.springframework.boot.ApplicationArguments
import org.springframework.boot.ApplicationRunner
import org.springframework.boot.ExitCodeGenerator
import org.springframework.boot.SpringApplication
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty
import org.springframework.context.ConfigurableApplicationContext
import org.springframework.core.Ordered
import org.springframework.core.annotation.Order
import org.springframework.core.env.Environment
import org.springframework.stereotype.Component
import kotlin.system.exitProcess

@Component
@Order(Ordered.LOWEST_PRECEDENCE)
@ConditionalOnProperty(prefix = "app", name = ["backfill-book-covers"], havingValue = "true")
class BookCoverBackfillRunner(
    private val backfillService: BookCoverBackfillService,
    private val environment: Environment,
    private val applicationContext: ConfigurableApplicationContext,
) : ApplicationRunner {
    private val logger = LoggerFactory.getLogger(javaClass)

    override fun run(args: ApplicationArguments) {
        val overwrite = environment.getProperty("app.backfill-book-covers-overwrite", Boolean::class.java, false)
        val result = backfillService.backfill(overwrite)
        logger.info(
            "Book cover backfill complete: candidates={}, stored={}, withoutCover={}, failed={}",
            result.candidates,
            result.stored,
            result.withoutCover,
            result.failed,
        )
        val exitCode = SpringApplication.exit(
            applicationContext,
            ExitCodeGenerator { if (result.failed == 0) 0 else 1 },
        )
        exitProcess(exitCode)
    }
}
