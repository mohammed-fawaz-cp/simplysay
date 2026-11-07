package com.comlabs.simplysay.call

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import java.io.OutputStream
import java.net.Socket
import java.nio.charset.StandardCharsets
import kotlin.concurrent.thread

class CallActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_ACCEPT = "com.comlabs.simplysay.ACTION_ACCEPT"
        const val ACTION_DECLINE = "com.comlabs.simplysay.ACTION_DECLINE"
        private const val TAG = "CallActionReceiver"
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

                // 3. Publish lightweight decentralized MQTT hangup packet directly to MQTT broker
                if (callCode.isNotEmpty()) {
                    publishMqttHangup(callCode, callerCit)
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
     * Publishes a pure decentralized MQTT 3.1.1 Hangup packet to notify the caller
     * even when the Flutter Dart VM is totally asleep or killed.
     */
    private fun publishMqttHangup(callCode: String, callerCit: String) {
        thread(isDaemon = true) {
            try {
                val cleanCode = callCode.replace("-", "").replace(" ", "").uppercase()
                val sessionTopic = "simplysay/call_session/$cleanCode/signaling"
                val payload = """{"signal_type":"hangup","type":"hangup","sender_id":"callee","from_cit":"callee","call_code":"$cleanCode","timestamp":${System.currentTimeMillis()}}"""

                val host = "159.89.166.217"
                val port = 1883

                Socket(host, port).use { socket ->
                    socket.soTimeout = 2000
                    val out: OutputStream = socket.getOutputStream()

                    // 1. MQTT CONNECT packet (Anonymous, clean session)
                    val clientId = "SS_Decline_" + (System.currentTimeMillis() % 100000)
                    val connectPacket = buildMqttConnectPacket(clientId)
                    out.write(connectPacket)
                    out.flush()

                    // 2. MQTT PUBLISH packet to session topic (QoS 0)
                    val publishPacket = buildMqttPublishPacket(sessionTopic, payload)
                    out.write(publishPacket)
                    out.flush()

                    // 3. Also publish to direct caller hangup topic if callerCit provided
                    if (callerCit.isNotBlank()) {
                        val directTopic = "simplysay/webrtc/live/hangup/$callerCit"
                        val directPacket = buildMqttPublishPacket(directTopic, payload)
                        out.write(directPacket)
                        out.flush()
                    }

                    Log.d(TAG, "✅ [MQTT Direct Decline] Dispatched hangup to $sessionTopic and caller $callerCit")
                }
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ Error sending direct MQTT decline: ${e.message}")
            }
        }
    }

    private fun buildMqttConnectPacket(clientId: String): ByteArray {
        val clientBytes = clientId.toByteArray(StandardCharsets.UTF_8)
        val protoName = "MQTT".toByteArray(StandardCharsets.UTF_8)
        val variableHeader = byteArrayOf(
            0x00, 0x04, protoName[0], protoName[1], protoName[2], protoName[3],
            0x04, // Protocol Level (3.1.1)
            0x02, // Clean Session flag
            0x00, 0x3C // Keep Alive (60s)
        )
        val payload = ByteArray(2 + clientBytes.size).apply {
            this[0] = (clientBytes.size shr 8).toByte()
            this[1] = (clientBytes.size and 0xFF).toByte()
            System.arraycopy(clientBytes, 0, this, 2, clientBytes.size)
        }
        val remainingLength = variableHeader.size + payload.size
        return byteArrayOf(0x10.toByte(), remainingLength.toByte()) + variableHeader + payload
    }

    private fun buildMqttPublishPacket(topic: String, payloadStr: String): ByteArray {
        val topicBytes = topic.toByteArray(StandardCharsets.UTF_8)
        val payloadBytes = payloadStr.toByteArray(StandardCharsets.UTF_8)

        val topicHeader = ByteArray(2 + topicBytes.size).apply {
            this[0] = (topicBytes.size shr 8).toByte()
            this[1] = (topicBytes.size and 0xFF).toByte()
            System.arraycopy(topicBytes, 0, this, 2, topicBytes.size)
        }

        val remainingLength = topicHeader.size + payloadBytes.size
        return byteArrayOf(0x30.toByte(), remainingLength.toByte()) + topicHeader + payloadBytes
    }
}
