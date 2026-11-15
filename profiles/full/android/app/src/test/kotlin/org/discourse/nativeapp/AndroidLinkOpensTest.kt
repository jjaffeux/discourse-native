package org.discourse.nativeapp

import android.content.Intent
import android.net.Uri
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class AndroidLinkOpensTest {
    private val links = AndroidLinkOpens()
    private val request = "discourse://open?url=https%3A%2F%2Fmeta.discourse.org%2Ft%2Fandroid%2F42"

    @Test
    fun coldStartRequestIsQueuedAndConsumedOnce() {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(request))
        links.didOpen(intent)
        links.didOpen(intent)
        val received = mutableListOf<String>()
        links.startDelivery { received += it }
        links.startDelivery { received += it }

        assertEquals(listOf(request), received)
    }

    @Test
    fun warmRequestsAreDeliveredAsTheyArrive() {
        val received = mutableListOf<String>()
        links.startDelivery { received += it }
        links.didOpen(Intent(Intent.ACTION_VIEW, Uri.parse(request)))
        links.didOpen(Intent(Intent.ACTION_VIEW, Uri.parse("$request%2F3")))

        assertEquals(listOf(request, "$request%2F3"), received)
    }

    @Test
    fun onlyTheOpenActionIsForwarded() {
        assertEquals(request, AndroidLinkOpens.request(Intent.ACTION_VIEW, request))
        assertNull(AndroidLinkOpens.request(Intent.ACTION_MAIN, request))
        assertNull(AndroidLinkOpens.request(Intent.ACTION_VIEW, null))
        assertNull(
            AndroidLinkOpens.request(Intent.ACTION_VIEW, "discourse://auth_redirect?payload=x"),
        )
        assertNull(AndroidLinkOpens.request(Intent.ACTION_VIEW, "https://meta.discourse.org/"))
        assertNull(
            AndroidLinkOpens.request(Intent.ACTION_VIEW, "discourse://open?url=" + "a".repeat(8192)),
        )
    }
}
