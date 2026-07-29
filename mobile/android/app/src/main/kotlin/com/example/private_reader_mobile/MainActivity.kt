package com.example.private_reader_mobile

import android.Manifest
import android.app.DownloadManager
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.view.Display
import android.view.Surface
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    private var pendingDownload: PendingDownload? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKUP_DOWNLOAD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "enqueue") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            enqueueBackupDownload(call, result)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        requestHighRefreshRate()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            requestHighRefreshRate()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != STORAGE_PERMISSION_REQUEST) return
        val pending = pendingDownload ?: return
        pendingDownload = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            performBackupDownload(pending.url, pending.fileName, pending.result)
        } else {
            pending.result.error("storage_permission_denied", "无法写入系统下载目录", null)
        }
    }

    private fun enqueueBackupDownload(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")?.trim().orEmpty()
        val fileName = call.argument<String>("fileName")?.trim().orEmpty()
        if ((!url.startsWith("https://") && !url.startsWith("http://")) || fileName.isBlank()) {
            result.error("invalid_download", "备份下载参数无效", null)
            return
        }
        if (
            Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingDownload = PendingDownload(url, fileName, result)
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                STORAGE_PERMISSION_REQUEST,
            )
            return
        }
        performBackupDownload(url, fileName, result)
    }

    private fun performBackupDownload(
        url: String,
        fileName: String,
        result: MethodChannel.Result,
    ) {
        val safeFileName = fileName.replace(Regex("[\\\\/:*?\"<>|]"), "-")
        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle(safeFileName)
            .setDescription("正在流式下载轻阅备份")
            .setMimeType("application/zip")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(false)
            .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, safeFileName)
        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        result.success(manager.enqueue(request))
    }

    private fun requestHighRefreshRate() {
        window.decorView.post { applyHighRefreshRate() }
        window.decorView.postDelayed({ applyHighRefreshRate() }, SURFACE_RETRY_DELAY_MS)
    }

    private fun applyHighRefreshRate() {
        val display = window.decorView.display ?: return
        val targetMode = findPreferredMode(display) ?: return
        val attributes = window.attributes
        attributes.preferredDisplayModeId = targetMode.modeId
        attributes.preferredRefreshRate = targetMode.refreshRate
        window.attributes = attributes
        requestSurfaceFrameRate(targetMode.refreshRate)
    }

    private fun requestSurfaceFrameRate(refreshRate: Float) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val flutterSurface = findFlutterSurface(window.decorView) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            flutterSurface.requestedFrameRate = refreshRate
        }
        val surface = flutterSurface.holder.surface
        if (!surface.isValid) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            surface.setFrameRate(
                refreshRate,
                Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE,
                Surface.CHANGE_FRAME_RATE_ALWAYS,
            )
        } else {
            surface.setFrameRate(refreshRate, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE)
        }
    }

    private fun findFlutterSurface(view: View): FlutterSurfaceView? {
        if (view is FlutterSurfaceView) return view
        if (view !is ViewGroup) return null
        for (index in 0 until view.childCount) {
            findFlutterSurface(view.getChildAt(index))?.let { return it }
        }
        return null
    }

    private fun findPreferredMode(display: Display): Display.Mode? {
        val currentMode = display.mode
        val matchingModes = display.supportedModes.filter { mode ->
            mode.physicalWidth == currentMode.physicalWidth &&
                mode.physicalHeight == currentMode.physicalHeight
        }
        val exactTarget = matchingModes.minByOrNull { mode ->
            abs(mode.refreshRate - TARGET_REFRESH_RATE)
        }
        if (exactTarget != null && abs(exactTarget.refreshRate - TARGET_REFRESH_RATE) <= 1f) {
            return exactTarget
        }
        return matchingModes
            .filter { mode -> mode.refreshRate <= TARGET_REFRESH_RATE + 1f }
            .maxByOrNull { mode -> mode.refreshRate }
            ?: matchingModes.maxByOrNull { mode -> mode.refreshRate }
    }

    private companion object {
        const val BACKUP_DOWNLOAD_CHANNEL =
            "com.privatereader.private_reader_mobile/backup_downloads"
        const val STORAGE_PERMISSION_REQUEST = 2407
        const val TARGET_REFRESH_RATE = 120f
        const val SURFACE_RETRY_DELAY_MS = 500L
    }

    private data class PendingDownload(
        val url: String,
        val fileName: String,
        val result: MethodChannel.Result,
    )
}
