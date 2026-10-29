package org.discourse.nativeapp

import android.net.Uri
import org.json.JSONException
import org.json.JSONObject

object DiscoursePushPayload {
    fun decode(payload: String?): JSONObject? = try {
        payload?.let { JSONObject(it) }
    } catch (_: JSONException) {
        null
    }

    fun url(payload: String?, directUrl: String? = null): String? {
        val value = directUrl ?: decode(payload)?.optString("discourse_url") ?: return null
        val uri = Uri.parse(value)
        return value.takeIf {
            (uri.scheme == "https" || uri.scheme == "http") && !uri.host.isNullOrEmpty()
        }
    }
}
