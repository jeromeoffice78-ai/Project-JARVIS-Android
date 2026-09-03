from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


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
    <uses-permission android:name="android.permission.health.READ_STEPS" />
    <uses-permission android:name="android.permission.health.READ_HEART_RATE" />
    <uses-permission android:name="android.permission.health.READ_RESTING_HEART_RATE" />
    <uses-permission android:name="android.permission.health.READ_OXYGEN_SATURATION" />
    <uses-permission android:name="android.permission.health.READ_SLEEP" />
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />

"""
    if "android.permission.ACCESS_FINE_LOCATION" not in text:
        text = text.replace("    <application", permissions + "    <application", 1)

    queries = """\
    <queries>
        <package android:name="com.google.android.apps.healthdata" />
        <intent><action android:name="android.speech.RecognitionService" /></intent>
        <intent><action android:name="android.intent.action.TTS_SERVICE" /></intent>
    </queries>

"""
    if "<queries>" not in text:
        text = text.replace("    <application", queries + "    <application", 1)

    activity_pattern = re.compile(
        r'(<activity\\b[^>]*android:name="\\.MainActivity"[^>]*>)(.*?)(</activity>)',
        re.DOTALL,
    )
    if "androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" not in text:
        def add_health_intent(match: re.Match[str]) -> str:
            return (
                match.group(1)
                + match.group(2)
                + """\
                <intent-filter>
                    <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />
                </intent-filter>
"""
                + match.group(3)
            )
        text, count = activity_pattern.subn(add_health_intent, text, count=1)
        if count == 0:
            raise RuntimeError("Could not locate MainActivity in AndroidManifest.xml")

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

    path.write_text(text, encoding="utf-8")


def patch_activity() -> None:
    candidates = list((ROOT / "android" / "app" / "src" / "main" / "kotlin").rglob("MainActivity.kt"))
    if not candidates:
        raise RuntimeError("Generated MainActivity.kt not found")
    path = candidates[0]
    text = path.read_text(encoding="utf-8")
    text = text.replace(
        "import io.flutter.embedding.android.FlutterActivity",
        "import io.flutter.embedding.android.FlutterFragmentActivity",
    ).replace(
        "class MainActivity : FlutterActivity()",
        "class MainActivity : FlutterFragmentActivity()",
    )
    path.write_text(text, encoding="utf-8")


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
    patch_manifest()
    patch_activity()
    patch_debug_manifest()
    patch_proguard()
    print("Project Jarvis Android host prepared.")


if __name__ == "__main__":
    main()
