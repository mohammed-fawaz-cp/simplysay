package com.comlabs.simplysay.call

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.comlabs.simplysay.MainActivity

class IncomingCallActivity : Activity() {

    private var callerName: String = "Someone"
    private var callerCit: String = ""
    private var callCode: String = ""
    private var sdpOffer: String? = null
    private var callType: String = "video"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 1. Wake up screen and show over lock screen
        setupLockScreenFlags()

        // 2. Parse Intent Extras
        callerName = intent.getStringExtra("caller_name") ?: "Someone"
        callerCit = intent.getStringExtra("caller_cit") ?: ""
        callCode = intent.getStringExtra("call_code") ?: ""
        sdpOffer = intent.getStringExtra("sdp_offer")
        callType = intent.getStringExtra("call_type") ?: "video"

        // 3. Build Dynamic Native UI matching SimplySay Design Tokens (Light/Dark)
        val isDarkMode = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val rootView = buildDynamicCallView(isDarkMode)
        setContentView(rootView)
    }

    private fun setupLockScreenFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    private fun buildDynamicCallView(isDark: Boolean): View {
        val bgColor = if (isDark) Color.parseColor("#131313") else Color.parseColor("#FAF9FD")
        val textColor = if (isDark) Color.parseColor("#E5E2E1") else Color.parseColor("#1A1B1E")
        val subTextColor = if (isDark) Color.parseColor("#94A3B8") else Color.parseColor("#414754")
        val avatarBg = if (isDark) Color.parseColor("#1E3A8A") else Color.parseColor("#004492")

        val root = FrameLayout(this).apply {
            setBackgroundColor(bgColor)
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

        val contentLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(48, 120, 48, 80)
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }

        // 1. Security Badge
        val securityBadge = TextView(this).apply {
            text = "🔒 End-to-End P2P Encrypted"
            setTextColor(if (isDark) Color.parseColor("#10B981") else Color.parseColor("#006E2C"))
            textSize = 12f
            gravity = Gravity.CENTER
            val badgeBg = GradientDrawable().apply {
                setColor(if (isDark) Color.parseColor("#1E293B") else Color.parseColor("#E2E8F0"))
                cornerRadius = 32f
            }
            background = badgeBg
            setPadding(28, 10, 28, 10)
        }
        contentLayout.addView(securityBadge)

        // 2. Call Type Label
        val callTypeLabel = TextView(this).apply {
            text = "INCOMING VIDEO CALL"
            setTextColor(subTextColor)
            textSize = 12f
            letterSpacing = 0.1f
            gravity = Gravity.CENTER
            setPadding(0, 24, 0, 48)
        }
        contentLayout.addView(callTypeLabel)

        // 3. Avatar View
        val initials = if (callerName.length >= 2) callerName.substring(0, 2).uppercase() else "SS"
        val avatarView = TextView(this).apply {
            text = initials
            setTextColor(Color.WHITE)
            textSize = 36f
            gravity = Gravity.CENTER
            val circleBg = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(avatarBg)
                setStroke(6, Color.parseColor("#3B82F6"))
            }
            background = circleBg
            layoutParams = LinearLayout.LayoutParams(220, 220).apply {
                gravity = Gravity.CENTER_HORIZONTAL
            }
        }
        contentLayout.addView(avatarView)

        // 4. Caller Name
        val nameView = TextView(this).apply {
            text = callerName
            setTextColor(textColor)
            textSize = 26f
            gravity = Gravity.CENTER
            setPadding(0, 36, 0, 8)
        }
        contentLayout.addView(nameView)

        // 5. Caller CIT / Subtitle
        val citView = TextView(this).apply {
            text = if (callerCit.isNotEmpty()) "CIT: $callerCit" else "SimplySay Direct Call"
            setTextColor(subTextColor)
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 24)
        }
        contentLayout.addView(citView)

        // Spacer
        val spacer = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(0, 0, 1.0f)
        }
        contentLayout.addView(spacer)

        // 6. Action Buttons (Decline & Accept)
        val actionsLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

        // Decline Button
        val declineBtn = Button(this).apply {
            text = "✕ Decline"
            setTextColor(Color.WHITE)
            textSize = 16f
            val decBg = GradientDrawable().apply {
                setColor(Color.parseColor("#BA1A1A"))
                cornerRadius = 48f
            }
            background = decBg
            layoutParams = LinearLayout.LayoutParams(300, 140).apply {
                setMargins(16, 0, 24, 0)
            }
            setOnClickListener {
                onDeclinePressed()
            }
        }
        actionsLayout.addView(declineBtn)

        // Accept Button
        val acceptBtn = Button(this).apply {
            text = "📹 Accept"
            setTextColor(Color.WHITE)
            textSize = 16f
            val accBg = GradientDrawable().apply {
                setColor(Color.parseColor("#006E2C"))
                cornerRadius = 48f
            }
            background = accBg
            layoutParams = LinearLayout.LayoutParams(300, 140).apply {
                setMargins(24, 0, 16, 0)
            }
            setOnClickListener {
                onAcceptPressed()
            }
        }
        actionsLayout.addView(acceptBtn)

        contentLayout.addView(actionsLayout)
        root.addView(contentLayout)
        return root
    }

    private fun onDeclinePressed() {
        CallNotificationManager.dismissNotification(this)
        val intent = Intent(this, CallActionReceiver::class.java).apply {
            action = CallActionReceiver.ACTION_DECLINE
            putExtra("call_code", callCode)
            putExtra("caller_cit", callerCit)
        }
        sendBroadcast(intent)
        finish()
    }

    private fun onAcceptPressed() {
        CallNotificationManager.dismissNotification(this)
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("action", "accept_call")
            putExtra("caller_name", callerName)
            putExtra("caller_cit", callerCit)
            putExtra("call_code", callCode)
            putExtra("sdp_offer", sdpOffer)
            putExtra("call_type", callType)
        }
        startActivity(intent)
        finish()
    }
}
