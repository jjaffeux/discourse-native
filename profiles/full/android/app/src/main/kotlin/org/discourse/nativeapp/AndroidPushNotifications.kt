package org.discourse.nativeapp

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AndroidPushNotifications(private val activity: Activity) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private var registrationChannel: MethodChannel? = null
    private var openChannel: EventChannel? = null
    private var badgeChannel: MethodChannel? = null
    private var badgeCount: Int? = null
    private var openSink: EventChannel.EventSink? = null
    private val pendingUrls = ArrayDeque<String>()
    private val pendingRegistrations = mutableListOf<MethodChannel.Result>()

    fun attach(messenger: BinaryMessenger) {
        DiscourseMessagingService.createNotificationChannel(activity)
        registrationChannel = MethodChannel(
            messenger, "org.discourse.native/push_notifications",
        ).also { it.setMethodCallHandler(this) }
        openChannel = EventChannel(
            messenger, "org.discourse.native/notification_opens",
        ).also { it.setStreamHandler(this) }
        badgeChannel = MethodChannel(messenger, "org.discourse.native/app_badge").also {
            it.setMethodCallHandler { call, result ->
                val count = call.arguments as? Int
                if (call.method != "setBadgeCount" || count == null) {
                    result.notImplemented()
                } else {
                    setBadgeCount(count)
                    result.success(null)
                }
            }
        }
    }

    // Android has no badge of its own: launchers count this app's delivered
    // notifications. Reading everything in the app therefore clears those the
    // forum sent. A zero that follows no count is a launch that has not read
    // anything yet, and must leave unseen notifications alone.
    fun setBadgeCount(count: Int) {
        val previous = badgeCount
        badgeCount = count
        if (count > 0 || previous == null || previous <= 0) return
        DiscourseMessagingService.cancelDelivered(activity)
    }

    fun detach() {
        registrationChannel?.setMethodCallHandler(null)
        badgeChannel?.setMethodCallHandler(null)
        openChannel?.setStreamHandler(null)
        openSink = null
        completeRegistration(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "currentRegistrationToken") {
            currentToken(result)
            return
        }
        if (call.method != "registrationToken") {
            result.notImplemented()
            return
        }
        pendingRegistrations.add(result)
        if (pendingRegistrations.size > 1) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            activity.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST,
            )
        } else {
            registrationToken()
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST || pendingRegistrations.isEmpty()) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            registrationToken()
        } else {
            completeRegistration(null)
        }
    }

    // Answers only what is already allowed: a launch or resume check must
    // never raise the permission dialog.
    private fun currentToken(result: MethodChannel.Result) {
        val notifications = activity.getSystemService(NotificationManager::class.java)
        val denied = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        if (denied || !notifications.areNotificationsEnabled()) {
            result.success(null)
            return
        }
        try {
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                result.success(if (task.isSuccessful) task.result else null)
            }
        } catch (_: IllegalStateException) {
            result.success(null)
        }
    }

    private fun registrationToken() {
        val notifications = activity.getSystemService(NotificationManager::class.java)
        if (!notifications.areNotificationsEnabled()) {
            completeRegistration(null)
            return
        }
        try {
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                completeRegistration(if (task.isSuccessful) task.result else null)
            }
        } catch (_: IllegalStateException) {
            completeRegistration(null)
        }
    }

    private fun completeRegistration(token: String?) {
        val pending = pendingRegistrations.toList()
        pendingRegistrations.clear()
        pending.forEach { it.success(token) }
    }

    fun didOpen(intent: Intent?) {
        val url = DiscoursePushPayload.url(
            intent?.getStringExtra("payload"), intent?.getStringExtra("discourse_url"),
        ) ?: return
        // Consume the extras so activity recreation cannot open the same tap twice.
        intent?.removeExtra("payload")
        intent?.removeExtra("discourse_url")
        val sink = openSink
        if (sink != null) {
            sink.success(url)
        } else {
            pendingUrls.addLast(url)
            if (pendingUrls.size > 16) pendingUrls.removeFirst()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        openSink = events
        while (pendingUrls.isNotEmpty()) events.success(pendingUrls.removeFirst())
    }

    override fun onCancel(arguments: Any?) {
        openSink = null
    }

    private companion object {
        const val PERMISSION_REQUEST = 4926
    }
}
