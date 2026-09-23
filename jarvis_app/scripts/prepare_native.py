from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch_gradle() -> None:
    path = ROOT / "android" / "app" / "build.gradle.kts"
    text = path.read_text(encoding="utf-8")
    text = text.replace(
        "minSdk = flutter.minSdkVersion",
        "minSdk = 26",
    )
    text = text.replace(
        "minSdk = 24",
        "minSdk = 26",
    )
    if "org.pytorch:executorch-android" not in text:
        text += """
dependencies {
    implementation("org.pytorch:executorch-android:1.3.0")
}
"""

    path.write_text(text, encoding="utf-8")


def patch_manifest() -> None:
    path = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    text = path.read_text(encoding="utf-8")

    permissions = """\
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACTIVITY_RECOGNITION" />
    <uses-permission android:name="android.permission.READ_CALENDAR" />
    <uses-permission android:name="android.permission.WRITE_CALENDAR" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.health.READ_STEPS" />
    <uses-permission android:name="android.permission.health.READ_HEART_RATE" />
    <uses-permission android:name="android.permission.health.READ_RESTING_HEART_RATE" />
    <uses-permission android:name="android.permission.health.READ_OXYGEN_SATURATION" />
    <uses-permission android:name="android.permission.health.READ_SLEEP" />
    <uses-permission android:name="android.permission.READ_PHONE_STATE" />
    <uses-permission android:name="android.permission.ANSWER_PHONE_CALLS" />
    <uses-permission android:name="android.permission.CALL_PHONE" />
    <uses-permission android:name="android.permission.READ_CALL_LOG" />
    <uses-permission android:name="android.permission.WRITE_CALL_LOG" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_PHONE_CALL" />
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />

"""
    if "android.permission.ACCESS_FINE_LOCATION" not in text:
        text = text.replace("    <application", permissions + "    <application", 1)
    elif "android.permission.ANSWER_PHONE_CALLS" not in text:
        text = text.replace(
            "    <application",
            """\
    <uses-permission android:name="android.permission.READ_PHONE_STATE" />
    <uses-permission android:name="android.permission.ANSWER_PHONE_CALLS" />
    <uses-permission android:name="android.permission.CALL_PHONE" />
    <uses-permission android:name="android.permission.READ_CALL_LOG" />
    <uses-permission android:name="android.permission.WRITE_CALL_LOG" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_PHONE_CALL" />

    <application""",
            1,
        )

    if "android.hardware.usb.host" not in text:
        text = text.replace(
            "    <application",
            '    <uses-feature android:name="android.hardware.usb.host" android:required="false" />\n\n    <application',
            1,
        )

    queries = """\
    <queries>
        <package android:name="com.google.android.apps.healthdata" />
        <intent><action android:name="android.speech.RecognitionService" /></intent>
        <intent><action android:name="android.intent.action.TTS_SERVICE" /></intent>
        <intent>
            <action android:name="android.intent.action.DIAL" />
            <data android:scheme="tel" />
        </intent>
    </queries>

"""
    if "<queries>" not in text:
        text = text.replace("    <application", queries + "    <application", 1)

    activity_pattern = re.compile(
        r'(<activity\b[^>]*android:name="\.MainActivity"[^>]*>)(.*?)(</activity>)',
        re.DOTALL,
    )

    def patch_main_activity(match: re.Match[str]) -> str:
        body = match.group(2)
        additions = ""

        if "android.intent.action.DIAL" not in body:
            additions += """\
                <intent-filter>
                    <action android:name="android.intent.action.DIAL" />
                    <category android:name="android.intent.category.DEFAULT" />
                </intent-filter>
                <intent-filter>
                    <action android:name="android.intent.action.DIAL" />
                    <category android:name="android.intent.category.DEFAULT" />
                    <data android:scheme="tel" />
                </intent-filter>
"""

        if "androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" not in body:
            additions += """\
                <intent-filter>
                    <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />
                </intent-filter>
"""

        return match.group(1) + body + additions + match.group(3)

    text, count = activity_pattern.subn(patch_main_activity, text, count=1)
    if count == 0:
        raise RuntimeError("Could not locate MainActivity in AndroidManifest.xml")

    if "JarvisInCallService" not in text:
        service = """\
        <service
            android:name=".JarvisInCallService"
            android:permission="android.permission.BIND_INCALL_SERVICE"
            android:exported="true">
            <meta-data
                android:name="android.telecom.IN_CALL_SERVICE_UI"
                android:value="true" />
            <intent-filter>
                <action android:name="android.telecom.InCallService" />
            </intent-filter>
        </service>
"""
        text = text.replace("    </application>", service + "    </application>", 1)

    if "ViewPermissionUsageActivity" not in text:
        alias = """\
        <activity-alias
            android:name="ViewPermissionUsageActivity"
            android:exported="true"
            android:targetActivity=".MainActivity"
            android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
            <intent-filter>
                <action android:name="android.intent.action.VIEW_PERMISSION_USAGE" />
                <category android:name="android.intent.category.HEALTH_PERMISSIONS" />
            </intent-filter>
        </activity-alias>
"""
        text = text.replace("    </application>", alias + "    </application>", 1)

    if "JarvisAccessibilityService" not in text:
        accessibility_service = """\
        <service
            android:name=".JarvisAccessibilityService"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"
            android:exported="true">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService" />
            </intent-filter>
            <meta-data
                android:name="android.accessibilityservice"
                android:resource="@xml/jarvis_accessibility_service" />
        </service>
"""
        text = text.replace(
            "    </application>",
            accessibility_service + "    </application>",
            1,
        )

    path.write_text(text, encoding="utf-8")


def patch_activity() -> None:
    candidates = list(
        (ROOT / "android" / "app" / "src" / "main" / "kotlin").rglob("MainActivity.kt")
    )
    if not candidates:
        raise RuntimeError("Generated MainActivity.kt not found")

    path = candidates[0]
    original = path.read_text(encoding="utf-8")
    package_match = re.search(r"^package\s+([\w.]+)", original, re.MULTILINE)
    if package_match is None:
        raise RuntimeError("Could not determine Android package name")

    package_name = package_match.group(1)

    main_activity = f"""package {package_name}

import android.app.role.RoleManager
import android.bluetooth.BluetoothManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.Settings
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbManager
import android.graphics.Color
import android.graphics.Paint
import android.graphics.pdf.PdfDocument
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import android.print.pdf.PrintedPdfDocument
import android.telecom.TelecomManager
import java.io.FileOutputStream
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {{
    private val phoneChannel = "jarvis.phone"
    private val printerChannel = "jarvis.printer"
    private val controlChannel = "jarvis.system_control"
    private val prefsName = "jarvis_phone"

    override fun onNewIntent(intent: Intent) {{
        super.onNewIntent(intent)
        setIntent(intent)
    }}

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)

        JarvisVoiceIdentityBridge.register(
            this,
            flutterEngine,
        )
        JarvisAppDistributionBridge.register(
            this,
            flutterEngine,
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            phoneChannel,
        ).setMethodCallHandler {{ call, result ->
            when (call.method) {{
                "isDefaultDialer" -> result.success(isDefaultDialer())
                "requestDefaultDialer" -> result.success(requestDefaultDialer())
                "consumeLaunchTarget" -> {{
                    val target =
                        intent?.getStringExtra("jarvis_launch_target").orEmpty()
                    intent?.removeExtra("jarvis_launch_target")
                    result.success(target)
                }}
                "getActiveCall" ->
                    result.success(JarvisInCallService.activeCallSnapshot())
                "answerActiveCall" ->
                    result.success(JarvisInCallService.answerActiveCall())
                "rejectActiveCall" ->
                    result.success(JarvisInCallService.rejectActiveCall())
                "disconnectActiveCall" ->
                    result.success(JarvisInCallService.disconnectActiveCall())
                "setMuted" -> {{
                    val muted = call.argument<Boolean>("muted") ?: false
                    result.success(JarvisInCallService.setCallMuted(muted))
                }}
                "setSpeaker" -> {{
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    result.success(JarvisInCallService.setSpeakerEnabled(enabled))
                }}
                "setAutoAnswer" -> {{
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                        .edit()
                        .putBoolean("auto_answer", enabled)
                        .apply()
                    result.success(true)
                }}
                "getAutoAnswer" -> {{
                    val enabled = getSharedPreferences(
                        prefsName,
                        Context.MODE_PRIVATE,
                    ).getBoolean("auto_answer", false)
                    result.success(enabled)
                }}
                "setGreeting" -> {{
                    val greeting = call.argument<String>("greeting")?.trim().orEmpty()
                    getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                        .edit()
                        .putString("greeting", greeting)
                        .apply()
                    result.success(true)
                }}
                "getGreeting" -> {{
                    val greeting = getSharedPreferences(
                        prefsName,
                        Context.MODE_PRIVATE,
                    ).getString(
                        "greeting",
                        "Hello. This is Jarvis. Jerome is unavailable. Please leave your name, number, and message.",
                    )
                    result.success(greeting)
                }}
                "listCallMessages" -> {{
                    val payload = getSharedPreferences(
                        prefsName,
                        Context.MODE_PRIVATE,
                    ).getString("call_messages", "[]")
                    result.success(payload ?: "[]")
                }}
                "clearCallMessages" -> {{
                    getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                        .edit()
                        .putString("call_messages", "[]")
                        .apply()
                    result.success(true)
                }}
                "placeCall" -> {{
                    val number = call.argument<String>("number")?.trim().orEmpty()
                    if (number.isEmpty()) {{
                        result.error("invalid_number", "Phone number is empty.", null)
                    }} else {{
                        try {{
                            val telecom =
                                getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                            telecom.placeCall(
                                android.net.Uri.parse("tel:$number"),
                                Bundle(),
                            )
                            result.success(true)
                        }} catch (error: Throwable) {{
                            result.error(
                                "place_call_failed",
                                error.message ?: "Unable to place call.",
                                null,
                            )
                        }}
                    }}
                }}
                else -> result.notImplemented()
            }}
        }}

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            controlChannel,
        ).setMethodCallHandler {{ call, result ->
            when (call.method) {{
                "isAccessibilityEnabled" ->
                    result.success(isAccessibilityEnabled())
                "openAccessibilitySettings" -> {{
                    startActivity(
                        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS),
                    )
                    result.success(true)
                }}
                "globalAction" -> {{
                    val action = call.argument<String>("action")?.trim().orEmpty()
                    val service = JarvisAccessibilityService.instance
                    result.success(
                        service?.performNamedGlobalAction(action) ?: false,
                    )
                }}
                "tap" -> {{
                    val x = call.argument<Double>("x") ?: -1.0
                    val y = call.argument<Double>("y") ?: -1.0
                    val service = JarvisAccessibilityService.instance
                    result.success(
                        service?.tap(x.toFloat(), y.toFloat()) ?: false,
                    )
                }}
                "swipe" -> {{
                    val startX = call.argument<Double>("startX") ?: -1.0
                    val startY = call.argument<Double>("startY") ?: -1.0
                    val endX = call.argument<Double>("endX") ?: -1.0
                    val endY = call.argument<Double>("endY") ?: -1.0
                    val durationMs =
                        call.argument<Int>("durationMs") ?: 350
                    val service = JarvisAccessibilityService.instance
                    result.success(
                        service?.swipe(
                            startX.toFloat(),
                            startY.toFloat(),
                            endX.toFloat(),
                            endY.toFloat(),
                            durationMs.toLong(),
                        ) ?: false,
                    )
                }}
                "typeText" -> {{
                    val text = call.argument<String>("text").orEmpty()
                    val service = JarvisAccessibilityService.instance
                    result.success(
                        service?.typeIntoFocusedField(text) ?: false,
                    )
                }}
                "launchApp" -> {{
                    val packageName =
                        call.argument<String>("packageName")?.trim().orEmpty()
                    if (packageName.isEmpty()) {{
                        result.success(false)
                    }} else {{
                        val launchIntent =
                            packageManager.getLaunchIntentForPackage(packageName)
                        if (launchIntent == null) {{
                            result.success(false)
                        }} else {{
                            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(launchIntent)
                            result.success(true)
                        }}
                    }}
                }}
                "captureScreenshot" -> {{
                    val service = JarvisAccessibilityService.instance
                    if (service == null) {{
                        result.error(
                            "accessibility_disabled",
                            "Enable Jarvis Accessibility Control first.",
                            null,
                        )
                    }} else {{
                        service.captureScreenshot(
                            onSuccess = {{ encoded ->
                                runOnUiThread {{
                                    result.success(encoded)
                                }}
                            }},
                            onError = {{ message ->
                                runOnUiThread {{
                                    result.error(
                                        "screenshot_failed",
                                        message,
                                        null,
                                    )
                                }}
                            }},
                        )
                    }}
                }}
                "listBondedBluetoothDevices" -> {{
                    result.success(listBondedBluetoothDevices())
                }}
                "openBluetoothSettings" -> {{
                    startActivity(
                        Intent(Settings.ACTION_BLUETOOTH_SETTINGS),
                    )
                    result.success(true)
                }}
                else -> result.notImplemented()
            }}
        }}

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            printerChannel,
        ).setMethodCallHandler {{ call, result ->
            when (call.method) {{
                "listUsbPrinters" -> result.success(listUsbPrinters())
                "getDeviceName" -> {{
                    val manufacturer = Build.MANUFACTURER
                        ?.trim()
                        ?.replaceFirstChar {{ if (it.isLowerCase()) it.titlecase() else it.toString() }}
                        .orEmpty()
                    val model = Build.MODEL?.trim().orEmpty()
                    result.success(
                        listOf(manufacturer, model)
                            .filter {{ it.isNotBlank() }}
                            .joinToString(" ")
                            .ifBlank {{ "Android device" }},
                    )
                }}
                "printTextDocument" -> {{
                    val title = call.argument<String>("title")?.trim().orEmpty()
                    val text = call.argument<String>("text")?.trim().orEmpty()

                    if (title.isEmpty() || text.isEmpty()) {{
                        result.error(
                            "invalid_document",
                            "A printable title and document body are required.",
                            null,
                        )
                    }} else {{
                        try {{
                            val printManager =
                                getSystemService(Context.PRINT_SERVICE) as PrintManager
                            val printJob = printManager.print(
                                title,
                                JarvisTextPrintAdapter(this, text),
                                PrintAttributes.Builder().build(),
                            )
                            result.success(printJob.id.toString())
                        }} catch (error: Throwable) {{
                            result.error(
                                "print_failed",
                                error.message ?: "Unable to start print job.",
                                null,
                            )
                        }}
                    }}
                }}
                "openPrintSettings" -> {{
                    try {{
                        startActivity(Intent(Settings.ACTION_PRINT_SETTINGS))
                        result.success(true)
                    }} catch (error: Throwable) {{
                        result.error(
                            "print_settings_failed",
                            error.message ?: "Unable to open print settings.",
                            null,
                        )
                    }}
                }}
                "printTestPage" -> {{
                    try {{
                        val printManager =
                            getSystemService(Context.PRINT_SERVICE) as PrintManager
                        val text =
                            "JARVIS printer test\\\\nHP OfficeJet 2620 USB/OTG path\\\\nAndroid system print framework"
                        printManager.print(
                            "JARVIS Test Print",
                            JarvisTextPrintAdapter(this, text),
                            PrintAttributes.Builder().build(),
                        )
                        result.success(true)
                    }} catch (error: Throwable) {{
                        result.error(
                            "print_failed",
                            error.message ?: "Unable to start print job.",
                            null,
                        )
                    }}
                }}
                else -> result.notImplemented()
            }}
        }}
    }}

    private fun isAccessibilityEnabled(): Boolean {{
        val expected = ComponentName(
            this,
            JarvisAccessibilityService::class.java,
        ).flattenToString()

        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false

        return enabled
            .split(':')
            .any {{ it.equals(expected, ignoreCase = true) }}
    }}

    private fun listBondedBluetoothDevices(): List<Map<String, Any?>> {{
        return try {{
            val manager =
                getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            val adapter = manager.adapter ?: return emptyList()

            adapter.bondedDevices.map {{ device ->
                mapOf(
                    "name" to (
                        try {{
                            device.name ?: "Bluetooth device"
                        }} catch (_: SecurityException) {{
                            "Bluetooth device"
                        }}
                    ),
                    "address" to device.address,
                    "type" to device.type,
                    "bondState" to device.bondState,
                )
            }}
        }} catch (_: SecurityException) {{
            emptyList()
        }}
    }}

    private fun listUsbPrinters(): List<Map<String, Any?>> {{
        val manager =
            getSystemService(Context.USB_SERVICE) as UsbManager

        return manager.deviceList.values.map {{ device ->
            var printerClass = device.deviceClass == UsbConstants.USB_CLASS_PRINTER

            for (index in 0 until device.interfaceCount) {{
                if (device.getInterface(index).interfaceClass ==
                    UsbConstants.USB_CLASS_PRINTER
                ) {{
                    printerClass = true
                    break
                }}
            }}

            val manufacturer = try {{
                device.manufacturerName ?: ""
            }} catch (_: Throwable) {{
                ""
            }}

            val product = try {{
                device.productName ?: ""
            }} catch (_: Throwable) {{
                ""
            }}

            mapOf(
                "deviceName" to device.deviceName,
                "vendorId" to device.vendorId,
                "productId" to device.productId,
                "manufacturer" to manufacturer,
                "productName" to product,
                "isPrinterClass" to printerClass,
                "isHpDevice" to (device.vendorId == 0x03F0),
            )
        }}
    }}

    private fun isDefaultDialer(): Boolean {{
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {{
            val roleManager = getSystemService(RoleManager::class.java)
            roleManager.isRoleAvailable(RoleManager.ROLE_DIALER) &&
                roleManager.isRoleHeld(RoleManager.ROLE_DIALER)
        }} else {{
            val telecom =
                getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            telecom.defaultDialerPackage == packageName
        }}
    }}

    private fun requestDefaultDialer(): Boolean {{
        return try {{
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {{
                val roleManager = getSystemService(RoleManager::class.java)
                if (!roleManager.isRoleAvailable(RoleManager.ROLE_DIALER)) {{
                    return false
                }}
                if (roleManager.isRoleHeld(RoleManager.ROLE_DIALER)) {{
                    return true
                }}
                startActivity(
                    roleManager.createRequestRoleIntent(RoleManager.ROLE_DIALER),
                )
                true
            }} else {{
                val intent = Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER)
                    .putExtra(
                        TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME,
                        packageName,
                    )
                startActivity(intent)
                true
            }}
        }} catch (_: Throwable) {{
            false
        }}
    }}
}}

class JarvisTextPrintAdapter(
    private val context: Context,
    private val text: String,
) : PrintDocumentAdapter() {{
    private var pdf: PrintedPdfDocument? = null

    override fun onLayout(
        oldAttributes: PrintAttributes?,
        newAttributes: PrintAttributes,
        cancellationSignal: CancellationSignal,
        callback: LayoutResultCallback,
        extras: Bundle?,
    ) {{
        pdf?.close()
        pdf = PrintedPdfDocument(context, newAttributes)

        if (cancellationSignal.isCanceled) {{
            callback.onLayoutCancelled()
            return
        }}

        callback.onLayoutFinished(
            PrintDocumentInfo.Builder("jarvis-test.pdf")
                .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                .setPageCount(1)
                .build(),
            true,
        )
    }}

    override fun onWrite(
        pages: Array<out PageRange>,
        destination: ParcelFileDescriptor,
        cancellationSignal: CancellationSignal,
        callback: WriteResultCallback,
    ) {{
        val document = pdf
        if (document == null) {{
            callback.onWriteFailed("Print document was not prepared.")
            return
        }}

        val page = document.startPage(0)
        val canvas = page.canvas
        val paint = Paint().apply {{
            color = Color.BLACK
            textSize = 18f
            isAntiAlias = true
        }}

        var y = 72f
        text.lines().forEach {{ line ->
            canvas.drawText(line, 54f, y, paint)
            y += 30f
        }}

        document.finishPage(page)

        try {{
            FileOutputStream(destination.fileDescriptor).use {{ output ->
                document.writeTo(output)
            }}
            callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
        }} catch (error: Throwable) {{
            callback.onWriteFailed(error.message)
        }} finally {{
            document.close()
            pdf = null
        }}
    }}

    override fun onFinish() {{
        pdf?.close()
        pdf = null
    }}
}}
"""
    path.write_text(main_activity, encoding="utf-8")

    voice_identity_template = (
        ROOT
        / "scripts"
        / "native"
        / "JarvisVoiceIdentityBridge.kt.template"
    )
    if not voice_identity_template.exists():
        raise RuntimeError(
            "JarvisVoiceIdentityBridge.kt.template is missing"
        )

    voice_identity_text = voice_identity_template.read_text(
        encoding="utf-8"
    ).replace("__PACKAGE__", package_name)

    (path.parent / "JarvisVoiceIdentityBridge.kt").write_text(
        voice_identity_text,
        encoding="utf-8",
    )

    app_distribution_template = (
        ROOT
        / "scripts"
        / "native"
        / "JarvisAppDistributionBridge.kt.template"
    )
    if not app_distribution_template.exists():
        raise RuntimeError(
            "JarvisAppDistributionBridge.kt.template is missing"
        )

    app_distribution_text = app_distribution_template.read_text(
        encoding="utf-8"
    ).replace("__PACKAGE__", package_name)

    (path.parent / "JarvisAppDistributionBridge.kt").write_text(
        app_distribution_text,
        encoding="utf-8",
    )

    service_path = path.parent / "JarvisInCallService.kt"
    service_path.write_text(
        f"""package {package_name}

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.InCallService
import android.telecom.VideoProfile
import org.json.JSONArray
import org.json.JSONObject

class JarvisInCallService : InCallService() {{
    companion object {{
        var instance: JarvisInCallService? = null
            private set
        var activeCall: Call? = null
            private set

        fun activeCallSnapshot(): Map<String, Any?>? {{
            val call = activeCall ?: return null
            val details = call.details
            val number =
                details.handle?.schemeSpecificPart ?: "Unknown caller"
            val incoming = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {{
                details.callDirection == Call.Details.DIRECTION_INCOMING
            }} else {{
                call.state == Call.STATE_RINGING
            }}
            val service = instance
            val audioState = service?.callAudioState
            val route = when (audioState?.route) {{
                CallAudioState.ROUTE_SPEAKER -> "speaker"
                CallAudioState.ROUTE_BLUETOOTH -> "bluetooth"
                CallAudioState.ROUTE_WIRED_HEADSET -> "wired_headset"
                CallAudioState.ROUTE_EARPIECE -> "earpiece"
                else -> "unknown"
            }}
            val state = when (call.state) {{
                Call.STATE_RINGING -> "ringing"
                Call.STATE_ACTIVE -> "active"
                Call.STATE_HOLDING -> "holding"
                Call.STATE_DIALING -> "dialing"
                Call.STATE_CONNECTING -> "connecting"
                Call.STATE_DISCONNECTED -> "disconnected"
                else -> "other"
            }}
            return mapOf(
                "phoneNumber" to number,
                "state" to state,
                "isIncoming" to incoming,
                "isMuted" to (audioState?.isMuted ?: false),
                "audioRoute" to route,
            )
        }}

        fun answerActiveCall(): Boolean {{
            val call = activeCall ?: return false
            return try {{
                call.answer(VideoProfile.STATE_AUDIO_ONLY)
                true
            }} catch (_: Throwable) {{
                false
            }}
        }}

        fun rejectActiveCall(): Boolean {{
            val call = activeCall ?: return false
            return try {{
                if (call.state == Call.STATE_RINGING) {{
                    call.reject(false, null)
                }} else {{
                    call.disconnect()
                }}
                true
            }} catch (_: Throwable) {{
                false
            }}
        }}

        fun disconnectActiveCall(): Boolean {{
            val call = activeCall ?: return false
            return try {{
                call.disconnect()
                true
            }} catch (_: Throwable) {{
                false
            }}
        }}

        fun setCallMuted(muted: Boolean): Boolean {{
            val service = instance ?: return false
            return try {{
                service.setMuted(muted)
                true
            }} catch (_: Throwable) {{
                false
            }}
        }}

        fun setSpeakerEnabled(enabled: Boolean): Boolean {{
            val service = instance ?: return false
            return try {{
                @Suppress("DEPRECATION")
                service.setAudioRoute(
                    if (enabled) {{
                        CallAudioState.ROUTE_SPEAKER
                    }} else {{
                        CallAudioState.ROUTE_EARPIECE
                    }},
                )
                true
            }} catch (_: Throwable) {{
                false
            }}
        }}
    }}

    private val prefsName = "jarvis_phone"
    private val channelId = "jarvis_calls"
    private val notificationId = 7731

    override fun onCreate() {{
        super.onCreate()
        instance = this
    }}

    override fun onDestroy() {{
        if (instance === this) {{
            instance = null
        }}
        activeCall = null
        super.onDestroy()
    }}

    override fun onCallAdded(call: Call) {{
        super.onCallAdded(call)
        activeCall = call
        super.onCallAdded(call)

        if (!isIncoming(call)) {{
            return
        }}

        val number =
            call.details.handle?.schemeSpecificPart ?: "Unknown caller"

        saveCallEvent(
            phoneNumber = number,
            status = "ringing",
            note = "Incoming call detected by Jarvis.",
        )

        showIncomingCallNotification(number)

        val autoAnswer = getSharedPreferences(
            prefsName,
            Context.MODE_PRIVATE,
        ).getBoolean("auto_answer", false)

        if (autoAnswer && call.state == Call.STATE_RINGING) {{
            try {{
                call.answer(VideoProfile.STATE_AUDIO_ONLY)
                saveCallEvent(
                    phoneNumber = number,
                    status = "answered",
                    note = "Jarvis answered the call. Spoken-message transcription requires the receptionist bridge.",
                )
            }} catch (_: Throwable) {{
                saveCallEvent(
                    phoneNumber = number,
                    status = "answer_failed",
                    note = "Android did not allow Jarvis to answer this call.",
                )
            }}
        }}

        call.registerCallback(
            object : Call.Callback() {{
                override fun onStateChanged(call: Call, state: Int) {{
                    if (state == Call.STATE_DISCONNECTED) {{
                        saveCallEvent(
                            phoneNumber = number,
                            status = "ended",
                            note = "Call ended.",
                        )
                        cancelIncomingCallNotification()
                        call.unregisterCallback(this)
                    }}
                }}
            }},
        )
    }}

    override fun onCallRemoved(call: Call) {{
        super.onCallRemoved(call)
        if (activeCall === call) {{
            activeCall = null
        }}
        cancelIncomingCallNotification()
    }}

    private fun isIncoming(call: Call): Boolean {{
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {{
            call.details.callDirection == Call.Details.DIRECTION_INCOMING
        }} else {{
            call.state == Call.STATE_RINGING
        }}
    }}

    private fun saveCallEvent(
        phoneNumber: String,
        status: String,
        note: String,
    ) {{
        val prefs = getSharedPreferences(
            prefsName,
            Context.MODE_PRIVATE,
        )
        val existing = prefs.getString("call_messages", "[]") ?: "[]"
        val oldArray = try {{
            JSONArray(existing)
        }} catch (_: Throwable) {{
            JSONArray()
        }}

        val newArray = JSONArray()
        val event = JSONObject()
            .put("id", System.currentTimeMillis().toString())
            .put("phone_number", phoneNumber)
            .put("timestamp", System.currentTimeMillis())
            .put("status", status)
            .put("message", note)

        newArray.put(event)

        val maxItems = minOf(oldArray.length(), 99)
        for (index in 0 until maxItems) {{
            newArray.put(oldArray.get(index))
        }}

        prefs.edit()
            .putString("call_messages", newArray.toString())
            .apply()
    }}

    private fun showIncomingCallNotification(phoneNumber: String) {{
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {{
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "Jarvis Calls",
                    NotificationManager.IMPORTANCE_HIGH,
                ),
            )
        }}

        val launchIntent =
            packageManager.getLaunchIntentForPackage(packageName)?.apply {{
                putExtra("jarvis_launch_target", "phone")
            }}
        val pendingIntent = launchIntent?.let {{
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }}

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {{
            Notification.Builder(this, channelId)
        }} else {{
            Notification.Builder(this)
        }}

        builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("Incoming call")
            .setContentText("$phoneNumber — Jarvis Phone Receptionist")
            .setCategory(Notification.CATEGORY_CALL)
            .setOngoing(true)
            .setPriority(Notification.PRIORITY_MAX)
            .setAutoCancel(false)

        if (pendingIntent != null) {{
            builder.setContentIntent(pendingIntent)
            builder.setFullScreenIntent(pendingIntent, true)
        }}

        manager.notify(notificationId, builder.build())
    }}

    private fun cancelIncomingCallNotification() {{
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(notificationId)
    }}
}}
""",
        encoding="utf-8",
    )


    accessibility_path = path.parent / "JarvisAccessibilityService.kt"
    accessibility_path.write_text(
        f"""package {package_name}

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Bitmap
import android.graphics.Path
import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.io.ByteArrayOutputStream

class JarvisAccessibilityService : AccessibilityService() {{
    companion object {{
        var instance: JarvisAccessibilityService? = null
            private set
    }}

    override fun onServiceConnected() {{
        super.onServiceConnected()
        instance = this
    }}

    override fun onDestroy() {{
        if (instance === this) {{
            instance = null
        }}
        super.onDestroy()
    }}

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {{
        // Jarvis does not scrape accessibility events or credentials.
    }}

    override fun onInterrupt() {{
        // No continuous accessibility feedback stream is used.
    }}

    fun captureScreenshot(
        onSuccess: (String) -> Unit,
        onError: (String) -> Unit,
    ) {{
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {{
            onError("Screen capture requires Android 11 or newer.")
            return
        }}

        takeScreenshot(
            Display.DEFAULT_DISPLAY,
            mainExecutor,
            object : TakeScreenshotCallback {{
                override fun onSuccess(
                    screenshot: ScreenshotResult,
                ) {{
                    val hardwareBuffer =
                        screenshot.hardwareBuffer

                    try {{
                        val hardwareBitmap =
                            Bitmap.wrapHardwareBuffer(
                                hardwareBuffer,
                                screenshot.colorSpace,
                            )

                        if (hardwareBitmap == null) {{
                            onError(
                                "Android returned no screenshot bitmap.",
                            )
                            return
                        }}

                        val softwareBitmap =
                            hardwareBitmap.copy(
                                Bitmap.Config.ARGB_8888,
                                false,
                            )

                        if (softwareBitmap == null) {{
                            onError(
                                "Could not convert the screenshot.",
                            )
                            return
                        }}

                        val output =
                            ByteArrayOutputStream()
                        softwareBitmap.compress(
                            Bitmap.CompressFormat.PNG,
                            100,
                            output,
                        )
                        softwareBitmap.recycle()

                        onSuccess(
                            Base64.encodeToString(
                                output.toByteArray(),
                                Base64.NO_WRAP,
                            ),
                        )
                    }} catch (error: Throwable) {{
                        onError(
                            error.message
                                ?: "Screen capture failed.",
                        )
                    }} finally {{
                        hardwareBuffer.close()
                    }}
                }}

                override fun onFailure(
                    errorCode: Int,
                ) {{
                    onError(
                        "Android screenshot failed with code $errorCode.",
                    )
                }}
            }},
        )
    }}

    fun typeIntoFocusedField(text: String): Boolean {{
        if (text.isEmpty()) {{
            return false
        }}

        val root = rootInActiveWindow ?: return false
        val focused = root.findFocus(
            AccessibilityNodeInfo.FOCUS_INPUT,
        ) ?: return false

        return try {{
            val arguments = Bundle().apply {{
                putCharSequence(
                    AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                    text,
                )
            }}
            focused.performAction(
                AccessibilityNodeInfo.ACTION_SET_TEXT,
                arguments,
            )
        }} finally {{
            focused.recycle()
            root.recycle()
        }}
    }}

    fun performNamedGlobalAction(action: String): Boolean {{
        val globalAction = when (action.lowercase()) {{
            "back" -> GLOBAL_ACTION_BACK
            "home" -> GLOBAL_ACTION_HOME
            "recents" -> GLOBAL_ACTION_RECENTS
            "notifications" -> GLOBAL_ACTION_NOTIFICATIONS
            "quick_settings" -> GLOBAL_ACTION_QUICK_SETTINGS
            else -> return false
        }}

        return performGlobalAction(globalAction)
    }}

    fun tap(x: Float, y: Float): Boolean {{
        if (x < 0f || y < 0f) {{
            return false
        }}

        val path = Path().apply {{
            moveTo(x, y)
        }}
        val gesture = GestureDescription.Builder()
            .addStroke(
                GestureDescription.StrokeDescription(
                    path,
                    0,
                    70,
                ),
            )
            .build()

        return dispatchGesture(
            gesture,
            null,
            null,
        )
    }}

    fun swipe(
        startX: Float,
        startY: Float,
        endX: Float,
        endY: Float,
        durationMs: Long,
    ): Boolean {{
        if (
            startX < 0f ||
            startY < 0f ||
            endX < 0f ||
            endY < 0f
        ) {{
            return false
        }}

        val path = Path().apply {{
            moveTo(startX, startY)
            lineTo(endX, endY)
        }}
        val gesture = GestureDescription.Builder()
            .addStroke(
                GestureDescription.StrokeDescription(
                    path,
                    0,
                    durationMs.coerceIn(100, 5000),
                ),
            )
            .build()

        return dispatchGesture(
            gesture,
            null,
            null,
        )
    }}
}}
""",
        encoding="utf-8",
    )

    accessibility_xml = (
        ROOT
        / "android"
        / "app"
        / "src"
        / "main"
        / "res"
        / "xml"
        / "jarvis_accessibility_service.xml"
    )
    accessibility_xml.parent.mkdir(parents=True, exist_ok=True)
    accessibility_xml.write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeWindowStateChanged"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:notificationTimeout="100"
    android:canPerformGestures="true"
    android:canRetrieveWindowContent="true"
    android:description="@string/app_name" />
""",
        encoding="utf-8",
    )


def patch_debug_manifest() -> None:
    path = ROOT / "android" / "app" / "src" / "debug" / "AndroidManifest.xml"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <application android:usesCleartextTraffic="true" />\n'
        '</manifest>\n',
        encoding="utf-8",
    )


def patch_proguard() -> None:
    path = ROOT / "android" / "app" / "proguard-rules.pro"
    path.write_text(
        "-keep class com.builttoroam.devicecalendar.** { *; }\n",
        encoding="utf-8",
    )


def main() -> None:
    patch_gradle()
    patch_manifest()
    patch_activity()
    patch_debug_manifest()
    patch_proguard()
    print("Project Jarvis Android host prepared.")


if __name__ == "__main__":
    main()
