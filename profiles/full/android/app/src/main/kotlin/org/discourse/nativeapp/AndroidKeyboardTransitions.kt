package org.discourse.nativeapp

import android.annotation.TargetApi
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsAnimation
import android.view.animation.Interpolator
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Announces each keyboard animation before its first frame, as the iOS runner
 * does, so sheets can move with the keyboard instead of after it. Earlier
 * Android versions report no animation and keep the settled-metrics fallback.
 */
class AndroidKeyboardTransitions {
    private var channel: MethodChannel? = null
    private var view: View? = null
    private var ready = false
    private var transition: Map<String, Any>? = null
    private var startedAt = 0L

    fun attach(messenger: BinaryMessenger, view: View) {
        channel = MethodChannel(messenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "keyboardReady" -> result.success(ready)
                    "keyboardTransition" -> result.success(
                        transition?.plus(
                            "elapsed" to (SystemClock.uptimeMillis() - startedAt) / 1000.0,
                        ),
                    )
                    else -> result.notImplemented()
                }
            }
        }
        this.view = view
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            view.setWindowInsetsAnimationCallback(Callback(view))
        }
    }

    fun detach() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            view?.setWindowInsetsAnimationCallback(null)
        }
        view = null
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun started(payload: Map<String, Any>, showing: Boolean) {
        startedAt = SystemClock.uptimeMillis()
        transition = payload
        channel?.invokeMethod("keyboardTransition", payload)
        if (showing) announceReady(false)
    }

    private fun announceReady(value: Boolean) {
        ready = value
        channel?.invokeMethod("keyboardReady", value)
    }

    @TargetApi(Build.VERSION_CODES.R)
    private inner class Callback(private val view: View) :
        WindowInsetsAnimation.Callback(DISPATCH_MODE_CONTINUE_ON_SUBTREE) {
        override fun onProgress(
            insets: WindowInsets,
            runningAnimations: MutableList<WindowInsetsAnimation>,
        ) = insets

        // The root insets already hold the animation's end state here.
        override fun onStart(
            animation: WindowInsetsAnimation,
            bounds: WindowInsetsAnimation.Bounds,
        ): WindowInsetsAnimation.Bounds {
            if (animation.typeMask and WindowInsets.Type.ime() != 0) {
                val insets = view.rootWindowInsets
                val bottom = if (insets?.isVisible(WindowInsets.Type.ime()) == true) {
                    insets.getInsets(WindowInsets.Type.ime()).bottom
                } else {
                    0
                }
                started(
                    payload(
                        bottom,
                        view.resources.displayMetrics.density,
                        animation.durationMillis,
                        animation.interpolator,
                    ),
                    showing = bottom > 0,
                )
            }
            return bounds
        }

        override fun onEnd(animation: WindowInsetsAnimation) {
            if (animation.typeMask and WindowInsets.Type.ime() == 0) return
            announceReady(view.rootWindowInsets?.isVisible(WindowInsets.Type.ime()) == true)
        }
    }

    companion object {
        const val CHANNEL = "org.discourse.native/keyboard"
        private const val SAMPLE_INTERVALS = 32

        /**
         * Flutter reports the settled keyboard as the IME's bottom inset in
         * logical pixels, so the target uses the same units.
         */
        fun payload(
            bottomPixels: Int,
            density: Float,
            durationMillis: Long,
            interpolator: Interpolator?,
        ): Map<String, Any> {
            val payload = mutableMapOf<String, Any>(
                "bottomInset" to bottomPixels / density.toDouble(),
                "duration" to maxOf(0L, durationMillis) / 1000.0,
                "elapsed" to 0.0,
                "curve" to LINEAR,
            )
            if (interpolator != null) {
                payload["samples"] = List(SAMPLE_INTERVALS + 1) {
                    interpolator.getInterpolation(it / SAMPLE_INTERVALS.toFloat()).toDouble()
                }
            }
            return payload
        }

        private const val LINEAR = 3
    }
}
