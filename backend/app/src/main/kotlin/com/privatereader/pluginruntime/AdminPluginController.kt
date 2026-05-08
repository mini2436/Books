package com.privatereader.pluginruntime

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/admin/plugins")
class AdminPluginController(
    private val pluginRegistryService: PluginRegistryService,
) {
    // 插件列表接口：返回当前后端已注册的图书格式插件和能力。
    @GetMapping
    fun listPlugins(): List<RegisteredPluginView> = pluginRegistryService.all()
}
