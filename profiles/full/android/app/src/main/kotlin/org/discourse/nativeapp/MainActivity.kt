package org.discourse.nativeapp

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val credentials = CredentialStorage(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "org.discourse.native/credentials",
        ).setMethodCallHandler { call, result ->
            try {
                val key = requireNotNull(call.argument<String>("key"))
                when (call.method) {
                    "read" -> result.success(credentials.read(key))
                    "write" -> {
                        credentials.write(key, requireNotNull(call.argument<String>("value")))
                        result.success(null)
                    }
                    "delete" -> {
                        credentials.delete(key)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                // Never include credentials or ciphertext in a platform error.
                result.error("credential_storage", "Credential storage failed", null)
            }
        }
    }
}
