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
@ConditionalOnProperty(prefix = "app", name = ["backfill-book-resources"], havingValue = "true")
class BookResourceBackfillRunner(
    private val backfillService: BookResourceBackfillService,
    private val environment: Environment,
    private val applicationContext: ConfigurableApplicationContext,
) : ApplicationRunner {
    private val logger = LoggerFactory.getLogger(javaClass)

    override fun run(args: ApplicationArguments) {
        val overwrite = environment.getProperty("app.backfill-book-resources-overwrite", Boolean::class.java, false)
        val result = backfillService.backfill(overwrite)
        logger.info(
            "Book resource backfill complete: books={}, referenced={}, stored={}, skipped={}, withoutResource={}, failedResources={}, failedBooks={}",
            result.books,
            result.referenced,
            result.stored,
            result.skipped,
            result.withoutResource,
            result.failedResources,
            result.failedBooks,
        )
        val exitCode = SpringApplication.exit(
            applicationContext,
            ExitCodeGenerator {
                if (result.failedBooks == 0 && result.failedResources == 0) 0 else 1
            },
        )
        exitProcess(exitCode)
    }
}
