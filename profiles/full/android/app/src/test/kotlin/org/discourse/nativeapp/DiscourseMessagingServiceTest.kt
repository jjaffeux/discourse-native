package org.discourse.nativeapp

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.os.Bundle
import com.google.firebase.messaging.RemoteMessage
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class DiscourseMessagingServiceTest {
    private val service = Robolectric.buildService(DiscourseMessagingService::class.java).create().get()
    private val notifications = service.getSystemService(NotificationManager::class.java)

    @Test
    fun foregroundMothershipMessageShowsNotificationAndKeepsItsDestination() {
        shadowOf(service.application).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        service.onMessageReceived(message("https://meta.discourse.org/t/android/42/3", "first"))

        val notification = notifications.activeNotifications.single().notification
        assertEquals("meta.discourse.org: Android push", notification.extras.getString(Notification.EXTRA_TITLE))
        assertEquals("alice mentioned you", notification.extras.getString(Notification.EXTRA_TEXT))
        assertEquals("discourse_notifications", notification.channelId)
        val intent = shadowOf(notification.contentIntent).savedIntent
        assertEquals("https://meta.discourse.org/t/android/42/3", intent.getStringExtra("discourse_url"))
        assertEquals(MainActivity::class.java.name, intent.component?.className)
    }

    @Test
    fun separateNotificationsKeepSeparateTapDestinations() {
        shadowOf(service.application).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        service.onMessageReceived(message("https://meta.discourse.org/t/first/1", "first"))
        service.onMessageReceived(message("https://meta.discourse.org/t/second/2", "second"))

        val destinations = notifications.activeNotifications.map {
            shadowOf(it.notification.contentIntent).savedIntent.getStringExtra("discourse_url")
        }.toSet()
        assertEquals(setOf(
            "https://meta.discourse.org/t/first/1", "https://meta.discourse.org/t/second/2",
        ), destinations)
    }

    @Test
    fun permissionDenialDoesNotDisplayNotification() {
        shadowOf(service.application).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        service.onMessageReceived(message("https://meta.discourse.org/t/android/42/3", "first"))

        assertTrue(notifications.activeNotifications.isEmpty())
    }

    private fun message(url: String, id: String) = RemoteMessage(Bundle().apply {
        putString("google.message_id", id)
        putString("gcm.n.e", "1")
        putString("gcm.n.title", "meta.discourse.org: Android push")
        putString("gcm.n.body", "alice mentioned you")
        putString("payload", """{"discourse_url":"$url","title":"meta.discourse.org","body":"alice mentioned you"}""")
    })
}
