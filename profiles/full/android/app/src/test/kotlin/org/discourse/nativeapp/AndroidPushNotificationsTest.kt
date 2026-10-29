package org.discourse.nativeapp

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class AndroidPushNotificationsTest {
    private val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
    private val push = AndroidPushNotifications(activity)

    @Test
    fun coldStartTapIsQueuedAndConsumedOnce() {
        val intent = Intent().putExtra(
            "payload", """{"discourse_url":"https://meta.discourse.org/t/android/42/3"}""",
        )
        push.didOpen(intent)
        push.didOpen(intent)
        val urls = mutableListOf<String>()
        push.onListen(null, urlSink(urls))
        push.onCancel(null)
        push.onListen(null, urlSink(urls))

        assertEquals(listOf("https://meta.discourse.org/t/android/42/3"), urls)
    }

    @Test
    fun warmTapsAndTapsWhileListenerRestartsAreDelivered() {
        val urls = mutableListOf<String>()
        push.onListen(null, urlSink(urls))
        push.didOpen(Intent().putExtra("discourse_url", "https://meta.discourse.org/t/first/1"))
        push.onCancel(null)
        push.didOpen(Intent().putExtra("discourse_url", "https://meta.discourse.org/t/second/2"))
        push.onListen(null, urlSink(urls))

        assertEquals(listOf(
            "https://meta.discourse.org/t/first/1", "https://meta.discourse.org/t/second/2",
        ), urls)
    }

    @Test
    fun malformedPayloadsAndNonWebLinksAreIgnored() {
        val urls = mutableListOf<String>()
        push.onListen(null, urlSink(urls))
        for (payload in listOf(
            "invalid-json", "{}", """{"discourse_url":"file:///private/file"}""",
            """{"discourse_url":"https:///missing-host"}""",
        )) {
            push.didOpen(Intent().putExtra("payload", payload))
        }
        assertTrue(urls.isEmpty())
    }

    @Test
    fun concurrentRegistrationsSharePermissionRequestAndDenialCompletesBoth() {
        val first = RegistrationResult()
        val second = RegistrationResult()
        push.onMethodCall(MethodCall("registrationToken", null), first)
        val requestCode = shadowOf(activity).lastRequestedPermission.requestCode
        push.onMethodCall(MethodCall("registrationToken", null), second)
        push.onRequestPermissionsResult(requestCode, intArrayOf(PackageManager.PERMISSION_DENIED))

        assertTrue(first.completed)
        assertTrue(second.completed)
        assertNull(first.token)
        assertNull(second.token)
    }

    @Test
    fun detachingCompletesPendingRegistrationWithoutPush() {
        val result = RegistrationResult()
        push.onMethodCall(MethodCall("registrationToken", null), result)
        push.detach()

        assertTrue(result.completed)
        assertNull(result.token)
    }

    private fun urlSink(urls: MutableList<String>) = object : EventChannel.EventSink {
        override fun success(event: Any?) { urls.add(event as String) }
        override fun error(code: String, message: String?, details: Any?) { fail(code) }
        override fun endOfStream() {}
    }

    private class RegistrationResult : MethodChannel.Result {
        var completed = false
        var token: Any? = null
        override fun success(result: Any?) {
            completed = true
            token = result
        }
        override fun error(code: String, message: String?, details: Any?) { fail(code) }
        override fun notImplemented() { fail("registrationToken must be supported") }
    }
}
