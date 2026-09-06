# JARVIS Shield Phase 1

## Goal
Build the native Android foundation for a defensive anti-scam and anti-spyware application targeting the REVVL Tab 2 on Android 15.

## Architecture
- UI: Jetpack Compose + Material 3
- Presentation: MVVM with StateFlow
- Domain: repository contracts and immutable models
- Data: Room for scan history and DataStore for preferences
- DI: Hilt
- Async: Kotlin Coroutines and Flow

## Phase 2 security engine
The next phase adds real defensive inspection using public Android APIs: installed application inventory, high-risk permission correlation, accessibility-service review, notification-listener review, device-admin review, overlay-risk analysis, installer/source analysis, package signature and SHA-256 inventory, and user-approved uninstall/settings remediation.

## Safety boundary
Android sandboxing prevents a normal app from silently deleting arbitrary apps, reading every app's private files, or guaranteeing detection of every possible malware family. This project will not request root access or use exploit-based removal. It will detect suspicious configurations and packages, explain the evidence, and hand off removal or revocation through Android's protected confirmation flows.
