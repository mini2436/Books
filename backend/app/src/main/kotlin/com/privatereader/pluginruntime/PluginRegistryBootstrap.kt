package com.privatereader.pluginruntime

import org.springframework.boot.ApplicationArguments
import org.springframework.boot.ApplicationRunner
import org.springframework.stereotype.Component

@Component
class PluginRegistryBootstrap(
    private val pluginRegistryService: PluginRegistryService,
) : ApplicationRunner {
    override fun run(args: ApplicationArguments?) {
        pluginRegistryService.syncRegistry()
    }
}

