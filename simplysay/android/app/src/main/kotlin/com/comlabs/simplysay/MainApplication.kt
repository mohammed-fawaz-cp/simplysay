package com.comlabs.simplysay

import android.content.Context
import com.comlabs.simplysay.call.NativeCallBridge
import io.flutter.app.FlutterApplication

class MainApplication : FlutterApplication() {
    companion object {
        @JvmStatic
        var appContext: Context? = null
    }

    override fun onCreate() {
        super.onCreate()
        appContext = applicationContext
        MainActivity.applicationContextInstance = applicationContext
        NativeCallBridge.appContext = applicationContext
    }
}
