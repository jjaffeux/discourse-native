package org.discourse.discourse_native

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var credentialsChannel: MethodChannel? = null
    private val credentialWork = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val storage = AndroidCredentialStore(applicationContext)
        credentialsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "org.discourse.native/credentials",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method !in setOf("read", "write", "delete")) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val key = call.argument<String>("key")
                val value = call.argument<String>("value")
                if (key == null || (call.method == "write" && value == null)) {
                    result.error("invalid_arguments", "Credential key/value required", null)
                    return@setMethodCallHandler
                }
                credentialWork.execute {
                    try {
                        val response = when (call.method) {
                            "read" -> storage.read(key)
                            "write" -> { storage.write(key, value!!); null }
                            else -> { storage.delete(key); null }
                        }
                        mainHandler.post { result.success(response) }
                    } catch (error: Exception) {
                        // Never return credential-bearing exception messages.
                        mainHandler.post {
                            result.error("credential_storage", error.javaClass.simpleName, null)
                        }
                    }
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        credentialsChannel?.setMethodCallHandler(null)
        credentialsChannel = null
        credentialWork.shutdown()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
