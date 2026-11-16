package org.discourse.nativeapp

import android.view.animation.PathInterpolator
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class AndroidKeyboardTransitionsTest {
    @Test
    fun targetUsesFlutterLogicalPixels() {
        val payload = AndroidKeyboardTransitions.payload(796, 2.625f, 285, null)

        assertEquals(796 / 2.625, payload["bottomInset"] as Double, 1e-9)
        assertEquals(0.285, payload["duration"] as Double, 1e-9)
        assertEquals(0.0, payload["elapsed"])
    }

    @Test
    fun interpolatorIsSampledEvenlyAcrossTheAnimation() {
        val interpolator = PathInterpolator(0.2f, 0f, 0f, 1f)
        val samples = AndroidKeyboardTransitions.payload(796, 2.625f, 285, interpolator)
            .getValue("samples") as List<*>

        assertEquals(33, samples.size)
        assertEquals(0.0, samples.first() as Double, 1e-6)
        assertEquals(1.0, samples.last() as Double, 1e-6)
        assertEquals(interpolator.getInterpolation(0.25f).toDouble(), samples[8] as Double, 1e-9)
    }

    @Test
    fun hidingAndUncontrolledAnimationsStayWellFormed() {
        val payload = AndroidKeyboardTransitions.payload(0, 2.625f, -1, null)

        assertEquals(0.0, payload["bottomInset"])
        assertEquals(0.0, payload["duration"])
        assertFalse(payload.containsKey("samples"))
    }
}
