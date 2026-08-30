package com.comlabs.simplysay

import android.content.Context
import android.content.Intent
import android.os.Bundle
import com.comlabs.simplysay.call.NativeCallBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    companion object {
        var applicationContextInstance: Context? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applicationContextInstance = applicationContext
        handleIncomingCallIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingCallIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        applicationContextInstance = applicationContext
        NativeCallBridge.registerWith(flutterEngine, applicationContext)
    }

    private fun handleIncomingCallIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.getStringExtra("action")
        if (action == "accept_call") {
            val callCode = intent.getStringExtra("call_code") ?: ""
            val callerCit = intent.getStringExtra("caller_cit") ?: ""
            val callerName = intent.getStringExtra("caller_name") ?: "Someone"
            val sdpOffer = intent.getStringExtra("sdp_offer")
            val callType = intent.getStringExtra("call_type") ?: "video"

            NativeCallBridge.sendCallEvent("call_accepted", mapOf(
                "call_code" to callCode,
                "caller_cit" to callerCit,
                "caller_name" to callerName,
                "sdp_offer" to sdpOffer,
                "call_type" to callType
            ))
        }
    }
}
