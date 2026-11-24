package org.discourse.nativeapp

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.content.IntentCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

internal class AndroidShares(private val context: Context) {
    private val pending = ArrayDeque<IncomingShare>()
    private var channel: MethodChannel? = null
    private var listening = false

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "org.discourse.native/android_shares").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "listen" -> {
                        listening = true
                        result.success(null)
                        while (pending.isNotEmpty()) deliver(pending.removeFirst())
                    }
                    "importMedia" -> {
                        val uris = call.argument<List<String>>("uris").orEmpty().map(Uri::parse)
                        val mimeType = call.argument<String>("mimeType")
                        executor.execute {
                            val media = importMedia(uris, mimeType)
                            main.post { result.success(media) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        listening = false
    }

    fun didReceive(intent: Intent?) {
        if (intent == null || !isShareAction(intent.action)) return
        val share = try {
            read(intent)
        } catch (_: RuntimeException) {
            null // External extras can contain malformed parcelables.
        } ?: IncomingShare(null, emptyList(), null)
        intent.action = null
        if (listening) {
            deliver(share)
        } else {
            pending.addLast(share)
            if (pending.size > 16) pending.removeFirst()
        }
    }

    private fun deliver(share: IncomingShare) {
        channel?.invokeMethod(
            "receive",
            mapOf(
                "text" to share.text,
                "uris" to share.uris.map(Uri::toString),
                "mimeType" to share.mimeType,
            ),
        )
    }

    private fun importMedia(uris: List<Uri>, mimeType: String?): Map<String, Any?> {
        val root = File(context.cacheDir, "android-shares")
        if (!cacheInitialized) {
            root.deleteRecursively()
            cacheInitialized = true
        }
        val directory = File(root, UUID.randomUUID().toString())
        val files = if (directory.mkdirs()) {
            uris.mapIndexedNotNull { index, uri ->
                copyMedia(uri, mimeType, File(directory, index.toString()))
            }
        } else {
            emptyList()
        }
        if (files.isEmpty()) directory.deleteRecursively()
        return mapOf(
            "directory" to directory.path.takeIf { files.isNotEmpty() },
            "files" to files,
        )
    }

    private fun copyMedia(uri: Uri, declaredType: String?, destination: File): Map<String, String>? {
        // Use the temporary URI permission granted for this share.
        if (uri.scheme != ContentResolver.SCHEME_CONTENT ||
            context.checkUriPermission(
                uri,
                Process.myPid(),
                Process.myUid(),
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            ) != PackageManager.PERMISSION_GRANTED
        ) return null

        val resolver = context.contentResolver
        try {
            val detectedType = resolver.getType(uri)
            val type = when (detectedType) {
                null, "application/octet-stream" -> declaredType
                else -> detectedType
            }?.takeIf(::isMediaType) ?: return null
            val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(type)
            val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                }
                ?.substringAfterLast('/')
                ?.substringAfterLast('\\')
                ?.replace(controlCharacters, "")
                ?.trim()
                ?.takeUnless { it.isEmpty() || it == "." || it == ".." }
                ?: "shared-media"
            val filename = if (name.substringAfterLast('.', "").isEmpty() && extension != null) {
                "$name.$extension"
            } else {
                name
            }
            val input = resolver.openInputStream(uri) ?: return null
            input.use { source -> destination.outputStream().use { source.copyTo(it) } }
            return mapOf("name" to filename, "path" to destination.path)
        } catch (_: IOException) {
            destination.delete()
            return null
        } catch (_: RuntimeException) {
            destination.delete()
            return null
        }
    }

    internal data class IncomingShare(
        val text: String?,
        val uris: List<Uri>,
        val mimeType: String?,
    )

    companion object {
        private val executor = Executors.newSingleThreadExecutor()
        private val main = Handler(Looper.getMainLooper())
        private val controlCharacters = Regex("[\\p{Cntrl}]")
        // Accessed only by the import executor.
        private var cacheInitialized = false

        private fun isShareAction(action: String?) =
            action == Intent.ACTION_SEND || action == Intent.ACTION_SEND_MULTIPLE

        private fun isMediaType(type: String) =
            type.startsWith("image/") || type.startsWith("video/")

        internal fun read(intent: Intent): IncomingShare? {
            if (!isShareAction(intent.action)) return null

            val type = intent.type
            val clip = intent.clipData
            val items = if (clip == null) emptyList() else List(clip.itemCount, clip::getItemAt)
            val multiple = intent.action == Intent.ACTION_SEND_MULTIPLE
            val text = if (multiple) {
                intent.getCharSequenceArrayListExtra(Intent.EXTRA_TEXT)
                    ?.filterNot { it.isBlank() }?.joinToString("\n\n")
                    ?: intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            } else {
                intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            }
            val body = text?.takeUnless(String::isBlank)
                ?: items.mapNotNull { it.text?.toString()?.takeUnless(String::isBlank) }
                    .joinToString("\n\n").takeUnless(String::isBlank)
            val uris = if (type?.startsWith("text/") == true) {
                // Link previews sometimes carry a thumbnail in ClipData.
                emptyList()
            } else {
                val streams = if (multiple) {
                    IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
                        .orEmpty()
                } else {
                    listOfNotNull(
                        IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java),
                    )
                }
                streams.ifEmpty { items.mapNotNull { it.uri } }.distinct()
            }
            return IncomingShare(body, uris, type)
        }
    }
}
