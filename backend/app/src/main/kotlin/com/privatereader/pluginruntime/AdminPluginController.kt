package com.privatereader.pluginruntime

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/admin/plugins")
class AdminPluginController(
    private val pluginRegistryService: PluginRegistryService,
) {
    @GetMapping
    fun listPlugins(): List<RegisteredPluginView> = pluginRegistryService.all()
}
