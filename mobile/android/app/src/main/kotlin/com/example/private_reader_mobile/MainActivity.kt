package com.example.private_reader_mobile

import android.os.Build
import android.os.Bundle
import android.view.Display
import android.view.Surface
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterSurfaceView
import kotlin.math.abs

class MainActivity : FlutterActivity() {
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
        const val TARGET_REFRESH_RATE = 120f
        const val SURFACE_RETRY_DELAY_MS = 500L
    }
}
