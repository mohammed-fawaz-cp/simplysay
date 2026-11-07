package com.comlabs.simplysay.call

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object NativeCallBridge : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private const val METHOD_CHANNEL_NAME = "com.comlabs.simplysay/call_bridge"
    private const val EVENT_CHANNEL_NAME = "com.comlabs.simplysay/call_events"

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    var appContext: Context? = null

    fun registerWithBinding(binding: io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        com.comlabs.simplysay.MainActivity.applicationContextInstance = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL_NAME).apply {
            setMethodCallHandler(this@NativeCallBridge)
        }
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL_NAME).apply {
            setStreamHandler(this@NativeCallBridge)
        }
        CallNotificationManager.createNotificationChannel(binding.applicationContext)
    }

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        com.comlabs.simplysay.MainActivity.applicationContextInstance = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL_NAME).apply {
            setMethodCallHandler(this@NativeCallBridge)
        }
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL_NAME).apply {
            setStreamHandler(this@NativeCallBridge)
        }
        CallNotificationManager.createNotificationChannel(binding.applicationContext)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
    }

    @JvmStatic
    fun registerWith(flutterEngine: FlutterEngine, context: Context?) {
        val ctx = context ?: appContext ?: com.comlabs.simplysay.MainActivity.applicationContextInstance
        if (ctx != null) {
            appContext = ctx
            com.comlabs.simplysay.MainActivity.applicationContextInstance = ctx
            CallNotificationManager.createNotificationChannel(ctx)
        }
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL_NAME).apply {
            setMethodCallHandler(this@NativeCallBridge)
        }
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL_NAME).apply {
            setStreamHandler(this@NativeCallBridge)
        }
    }

    private var ringtone: android.media.Ringtone? = null

    fun playRingtone(context: Context) {
        try {
            stopRingtone()
            val uri = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_RINGTONE)
            ringtone = android.media.RingtoneManager.getRingtone(context, uri)
            ringtone?.play()
        } catch (e: Exception) {
            android.util.Log.e("NativeCallBridge", "Error playing ringtone: $e")
        }
    }

    fun stopRingtone() {
        try {
            if (ringtone?.isPlaying == true) {
                ringtone?.stop()
            }
            ringtone = null
        } catch (e: Exception) {
            android.util.Log.e("NativeCallBridge", "Error stopping ringtone: $e")
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val targetContext = appContext ?: com.comlabs.simplysay.MainActivity.applicationContextInstance

        when (call.method) {
            "playRingtone" -> {
                if (targetContext != null) {
                    playRingtone(targetContext)
                    result.success(true)
                } else {
                    result.error("NO_CONTEXT", "Application context not initialized", null)
                }
            }
            "stopRingtone" -> {
                stopRingtone()
                result.success(true)
            }
            "showIncomingCall" -> {
                val callerName = call.argument<String>("caller_name") ?: "Someone"
                val callerCit = call.argument<String>("caller_cit") ?: ""
                val callCode = call.argument<String>("call_code") ?: ""
                val sdpOffer = call.argument<String>("sdp_offer")
                val callType = call.argument<String>("call_type") ?: "video"

                android.util.Log.d("NativeCallBridge", "🔔 showIncomingCall called: caller=$callerName, context=$targetContext")

                if (targetContext != null) {
                    CallNotificationManager.showIncomingCallNotification(
                        context = targetContext,
                        callerName = callerName,
                        callerCit = callerCit,
                        callCode = callCode,
                        sdpOffer = sdpOffer,
                        callType = callType
                    )
                    result.success(true)
                } else {
                    android.util.Log.e("NativeCallBridge", "❌ showIncomingCall failed: targetContext is null")
                    result.error("NO_CONTEXT", "Application context not initialized", null)
                }
            }
            "dismissIncomingCall" -> {
                stopRingtone()
                if (targetContext != null) {
                    CallNotificationManager.dismissNotification(targetContext)
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
