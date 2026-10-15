package org.discourse.discourse_native

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.security.KeyStore
import javax.crypto.AEADBadTagException
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidCredentialStoreTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val store = AndroidCredentialStore(context)
    private val key = "android-test::https://credentials.invalid"
    private val otherKey = "android-test::https://other.invalid"
    private val directory = File(context.noBackupFilesDir, "credentials-v1")

    @After
    fun cleanup() {
        store.delete(key)
        store.delete(otherKey)
    }

    @Test
    fun persistsReplacesAndDeletesWithoutPlaintextOnDisk() {
        store.delete(key)
        assertNull(store.read(key))
        store.write(key, "private-first-key")
        store.write(otherKey, "private-other-key")
        assertEquals("private-first-key", AndroidCredentialStore(context).read(key))
        assertTrue(directory.listFiles()!!.none {
            it.readBytes().toString(Charsets.UTF_8).contains("private-first-key")
        })
        val secret = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            .getKey("org.discourse.native.credentials.v1", null)
        assertNull(secret.encoded)
        store.write(key, "replacement")
        assertEquals("replacement", AndroidCredentialStore(context).read(key))
        store.delete(key)
        store.delete(key)
        assertNull(AndroidCredentialStore(context).read(key))
        assertEquals("private-other-key", store.read(otherKey))
    }

    @Test
    fun rejectsTamperedCiphertextWithoutDeletingIt() {
        store.write(key, "private-first-key")
        val digest = java.security.MessageDigest.getInstance("SHA-256")
            .digest(key.toByteArray()).joinToString("") { "%02x".format(it.toInt() and 0xff) }
        val file = File(directory, digest)
        val bytes = file.readBytes()
        bytes[bytes.lastIndex] = (bytes.last().toInt() xor 1).toByte()
        file.writeBytes(bytes)
        try {
            store.read(key)
            fail("Tampered ciphertext must fail authentication")
        } catch (_: AEADBadTagException) {
            assertArrayEquals(bytes, file.readBytes())
        }
    }

    @Test
    fun bindsCiphertextToItsCredentialKey() {
        store.write(key, "private-first-key")
        store.write(otherKey, "private-other-key")
        fun fileFor(value: String): File {
            val digest = java.security.MessageDigest.getInstance("SHA-256")
                .digest(value.toByteArray()).joinToString("") { "%02x".format(it.toInt() and 0xff) }
            return File(directory, digest)
        }
        fileFor(otherKey).writeBytes(fileFor(key).readBytes())
        try {
            store.read(otherKey)
            fail("Ciphertext from a different credential must fail authentication")
        } catch (_: AEADBadTagException) {
            assertEquals("private-first-key", store.read(key))
        }
    }
}
