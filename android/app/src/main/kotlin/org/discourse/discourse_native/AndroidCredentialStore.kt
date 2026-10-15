package org.discourse.discourse_native

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.io.IOException
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

// Called on MainActivity's serial worker. Ciphertext stays in no-backup storage;
// the AES key stays in Android Keystore and is never exported to Dart or disk.
internal class AndroidCredentialStore(context: Context) {
    private val directory = File(context.noBackupFilesDir, "credentials-v1")
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    fun read(key: String): String? {
        val file = fileFor(key)
        if (!exists(file)) return null
        val bytes = file.readFully()
        require(bytes.size >= 1 + IV_BYTES + TAG_BYTES && bytes[0] == VERSION) {
            "Invalid credential format"
        }
        val secret = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
            ?: throw IOException("Credential encryption key unavailable")
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            secret,
            GCMParameterSpec(TAG_BYTES * 8, bytes.copyOfRange(1, 1 + IV_BYTES)),
        )
        cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
        return cipher.doFinal(bytes.copyOfRange(1 + IV_BYTES, bytes.size))
            .toString(Charsets.UTF_8)
    }

    fun write(key: String, value: String) {
        if (!directory.isDirectory && !directory.mkdirs()) {
            throw IOException("Credential directory unavailable")
        }
        val secret = (keyStore.getKey(KEY_ALIAS, null) as? SecretKey) ?: newKey()
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secret)
        cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val file = fileFor(key)
        val stream = file.startWrite()
        try {
            stream.write(byteArrayOf(VERSION))
            stream.write(cipher.iv)
            stream.write(encrypted)
            stream.fd.sync()
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
    }

    fun delete(key: String) {
        val file = fileFor(key)
        file.delete()
        if (exists(file)) throw IOException("Credential deletion failed")
    }

    private fun exists(file: AtomicFile): Boolean =
        file.baseFile.exists() || File("${file.baseFile.path}.bak").exists()

    private fun fileFor(key: String): AtomicFile {
        // Hash names so neither site URLs nor raw key strings become paths.
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(key.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
        return AtomicFile(File(directory, digest))
    }

    private fun newKey(): SecretKey {
        // A missing key must not silently replace the key for retained records.
        if (directory.listFiles()?.any { it.isFile && !it.name.endsWith(".new") } == true) {
            throw IOException("Credential encryption key unavailable")
        }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setKeySize(256)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val KEY_ALIAS = "org.discourse.native.credentials.v1"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
        const val TAG_BYTES = 16
        const val VERSION: Byte = 1
    }
}
