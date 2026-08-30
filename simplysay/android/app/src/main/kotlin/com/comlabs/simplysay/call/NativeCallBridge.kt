package com.comlabs.simplysay.call

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object NativeCallBridge : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private const val METHOD_CHANNEL_NAME = "com.comlabs.simplysay/call_bridge"
    private const val EVENT_CHANNEL_NAME = "com.comlabs.simplysay/call_events"

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun registerWith(flutterEngine: FlutterEngine, context: Context) {
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL_NAME).apply {
            setMethodCallHandler(this@NativeCallBridge)
        }
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL_NAME).apply {
            setStreamHandler(this@NativeCallBridge)
        }
        CallNotificationManager.createNotificationChannel(context)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "showIncomingCall" -> {
                val callerName = call.argument<String>("caller_name") ?: "Someone"
                val callerCit = call.argument<String>("caller_cit") ?: ""
                val callCode = call.argument<String>("call_code") ?: ""
                val sdpOffer = call.argument<String>("sdp_offer")
                val callType = call.argument<String>("call_type") ?: "video"

                // Context is obtained from Application
                val appContext = com.comlabs.simplysay.MainActivity.applicationContextInstance
                if (appContext != null) {
                    CallNotificationManager.showIncomingCallNotification(
                        context = appContext,
                        callerName = callerName,
                        callerCit = callerCit,
                        callCode = callCode,
                        sdpOffer = sdpOffer,
                        callType = callType
                    )
                    result.success(true)
                } else {
                    result.error("NO_CONTEXT", "Application context not initialized", null)
                }
            }
            "dismissIncomingCall" -> {
                val appContext = com.comlabs.simplysay.MainActivity.applicationContextInstance
                if (appContext != null) {
                    CallNotificationManager.dismissNotification(appContext)
                    result.success(true)
                } else {
                    result.error("NO_CONTEXT", "Application context not initialized", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        this.eventSink = null
    }

    fun sendCallEvent(eventType: String, data: Map<String, Any?>) {
        mainHandler.post {
            val payload = HashMap<String, Any?>()
            payload["event"] = eventType
            payload.putAll(data)
            eventSink?.success(payload)
        }
    }
}
