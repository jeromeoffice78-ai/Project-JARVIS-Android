# JARVIS Shield

JARVIS Shield is a defensive Android security application designed for the REVVL Tab 2 and other modern Android devices.

## Current branch status

The `jarvis-shield` branch contains Phase 1 architecture plus the Phase 2 defensive security engine.

## Technology

- Kotlin
- Jetpack Compose + Material 3
- MVVM + Clean Architecture
- Hilt dependency injection
- Room scan-history persistence
- DataStore preferences
- Kotlin Coroutines and Flow

## Phase 2 protection engine

JARVIS Shield now performs an on-device heuristic inspection of installed applications. It correlates install source, granted sensitive permissions, Accessibility access, notification access, device-admin control, overlay capability, unknown-app installation capability, target SDK, debuggable state, signing-certificate SHA-256, and APK SHA-256 inventory for reviewed user apps.

The risk engine emphasizes dangerous combinations rather than treating an ordinary permission as proof of malware. Findings can be remediated through Android's protected app-details, permission, device-admin, special-access, and uninstall confirmation screens.

See `PHASE_2.md` for the exact scanner behavior and threat-model boundaries.

## Android security boundary

A normal Android app cannot silently uninstall arbitrary apps, inspect every other app's private files, or guarantee detection of every malware family. JARVIS Shield uses public Android APIs and user-approved remediation flows. It does not request root access or use exploit-based removal.

## Target

- Application ID: `com.jarvis.shield`
- Minimum Android: API 28
- Target Android: API 35
- Compile SDK: API 36
- Primary device: REVVL Tab 2 running Android 15
- Phase 2 version: `1.1.0-phase2` / version code `2`

## Next phase

Phase 3 will add the dedicated CI/CD pipeline for tests, lint, APK/AAB builds, signing, checksums, and release artifacts. That phase starts only after Phase 2 is confirmed functional.
