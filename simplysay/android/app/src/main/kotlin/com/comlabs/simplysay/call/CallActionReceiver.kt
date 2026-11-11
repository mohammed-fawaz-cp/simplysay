package com.comlabs.simplysay.call

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import kotlin.concurrent.thread

class CallActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_ACCEPT = "com.comlabs.simplysay.ACTION_ACCEPT"
        const val ACTION_DECLINE = "com.comlabs.simplysay.ACTION_DECLINE"
        private const val TAG = "CallActionReceiver"
        private const val BACKEND_DECLINE_URL = "https://simplysay.vercel.app/api/v1/fcm/decline-call"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val callCode = intent.getStringExtra("call_code") ?: ""
        val callerCit = intent.getStringExtra("caller_cit") ?: ""
        val callType = intent.getStringExtra("call_type") ?: "video"

        Log.d(TAG, "⚡ Received Call Action: $action for callCode: $callCode, callerCit: $callerCit, callType: $callType")

        when (action) {
            ACTION_DECLINE -> {
                // 1. Instantly dismiss Notification and stop ringtone
                NativeCallBridge.stopRingtone()
                CallNotificationManager.dismissNotification(context)

                // 2. Notify Flutter Engine if active
                NativeCallBridge.sendCallEvent("call_declined", mapOf(
                    "call_code" to callCode,
                    "caller_cit" to callerCit,
                    "call_type" to callType
                ))

                // 3. Dispatch secure HTTPS POST to backend to trigger MQTT decline without raw TCP sockets
                if (callCode.isNotEmpty() || callerCit.isNotEmpty()) {
                    sendDeclineToBackend(callCode, callerCit)
                }
            }
            ACTION_ACCEPT -> {
                NativeCallBridge.stopRingtone()
                CallNotificationManager.dismissNotification(context)
                NativeCallBridge.sendCallEvent("call_accepted", mapOf(
                    "call_code" to callCode,
                    "caller_cit" to callerCit,
                    "call_type" to callType
                ))
            }
        }
    }

    /**
     * Sends an HTTPS POST to the backend API which dispatches MQTT hangup to the caller
     * cleanly and securely without raw TCP sockets.
     */
    private fun sendDeclineToBackend(callCode: String, callerCit: String) {
        thread(isDaemon = true) {
            try {
                val url = URL(BACKEND_DECLINE_URL)
                val conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 4000
                    readTimeout = 4000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json; utf-8")
                    setRequestProperty("Accept", "application/json")
                }
                val jsonPayload = """{"call_code":"$callCode","caller_cit":"$callerCit","callee_cit":"callee"}"""
                conn.outputStream.use { os ->
                    val bytes = jsonPayload.toByteArray(StandardCharsets.UTF_8)
                    os.write(bytes, 0, bytes.size)
                }
                val code = conn.responseCode
                Log.d(TAG, "✅ [HTTPS Decline] Dispatched decline to backend, response code: $code")
                conn.disconnect()
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ [HTTPS Decline] Error dispatching decline: ${e.message}")
            }
        }
    }
}
