package org.discourse.nativeapp

import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Hands `discourse://open` requests to Dart unparsed: Dart owns their
 * validation. Sign-in's `discourse://auth_redirect` is a different host and is
 * delivered to the web-auth callback activity, never to this one.
 */
class AndroidLinkOpens {
    private var channel: MethodChannel? = null
    private var deliver: ((String) -> Unit)? = null
    private val pending = ArrayDeque<String>()

    fun attach(messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, "org.discourse.native/link_opens")
        channel.setMethodCallHandler { call, result ->
            if (call.method == "listen") {
                result.success(null)
                startDelivery { channel.invokeMethod("open", it) }
            } else {
                result.notImplemented()
            }
        }
        this.channel = channel
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        deliver = null
    }

    fun didOpen(intent: Intent?) {
        val request = request(intent?.action, intent?.dataString) ?: return
        // Consume the data so activity recreation cannot open the same link twice.
        intent?.data = null
        val deliver = deliver
        if (deliver != null) {
            deliver(request)
        } else {
            // A request can launch the app before Dart is listening.
            pending.addLast(request)
            if (pending.size > 16) pending.removeFirst()
        }
    }

    fun startDelivery(deliver: (String) -> Unit) {
        this.deliver = deliver
        while (pending.isNotEmpty()) deliver(pending.removeFirst())
    }

    companion object {
        private const val MAXIMUM_REQUEST_LENGTH = 8192

        fun request(action: String?, data: String?): String? {
            if (action != Intent.ACTION_VIEW || data == null) return null
            if (data.length > MAXIMUM_REQUEST_LENGTH) return null
            return if (data.startsWith("discourse://open?", ignoreCase = true)) data else null
        }
    }
}
