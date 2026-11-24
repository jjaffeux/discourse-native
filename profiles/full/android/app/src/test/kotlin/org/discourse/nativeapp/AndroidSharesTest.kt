package org.discourse.nativeapp

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class AndroidSharesTest {
    @Test
    fun linkShareKeepsTextAndIgnoresPreviewThumbnail() {
        val url = "https://example.test/video"
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, url)
            clipData = ClipData.newRawUri("Preview", Uri.parse("content://sender/thumbnail"))
        }

        assertEquals(AndroidShares.IncomingShare(url, emptyList(), "text/plain"), AndroidShares.read(intent))
    }

    @Test
    fun mixedMediaShareKeepsCaptionAndUsesStreamsInOrder() {
        val photo = Uri.parse("content://sender/photo")
        val video = Uri.parse("content://sender/video")
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = "*/*"
            putCharSequenceArrayListExtra(Intent.EXTRA_TEXT, arrayListOf("A caption"))
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, arrayListOf(photo, video))
            clipData = ClipData.newRawUri("Photo", photo)
        }

        assertEquals(
            AndroidShares.IncomingShare("A caption", listOf(photo, video), "*/*"),
            AndroidShares.read(intent),
        )
    }

    @Test
    fun clipOnlyPhotoIsAcceptedButViewIntentsAreIgnored() {
        val photo = Uri.parse("content://sender/photo")
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            clipData = ClipData.newRawUri("Photo", photo)
        }

        assertEquals(AndroidShares.IncomingShare(null, listOf(photo), "image/png"), AndroidShares.read(intent))
        intent.action = Intent.ACTION_VIEW
        assertNull(AndroidShares.read(intent))
    }
}
