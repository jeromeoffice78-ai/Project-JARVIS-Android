# JARVIS Shield

JARVIS Shield is a defensive Android security application designed for the REVVL Tab 2 and other modern Android devices.

## Phase 1 scope

This phase creates a clean native Android foundation using Kotlin, Jetpack Compose, MVVM, Clean Architecture, Hilt, Room, DataStore, Coroutines, and Flow. It intentionally does not claim to perform malware detection yet.

The Phase 2 security engine will add installed-app risk analysis, dangerous-permission correlation, accessibility-service review, notification-listener review, device-admin review, overlay-risk checks, installer/source analysis, package signature and SHA-256 inventory, secure uninstall handoff, and defensive settings guidance.

## Android security boundary

A normal Android app cannot silently uninstall arbitrary apps, inspect every other app's private files, or guarantee detection of every malware family. JARVIS Shield will use public Android APIs, policy-compliant package visibility, user-approved removal flows, and defense-in-depth checks. Root access is not required and will not be requested.

## Target

- Application ID: `com.jarvis.shield`
- Minimum Android: API 28
- Target Android: API 35
- Compile SDK: API 36
- Primary target device: REVVL Tab 2 running Android 15

## Build

Phase 1 is committed as a standalone Gradle project under `jarvis_shield/`. Build automation is intentionally deferred until Phase 3 in accordance with the staged delivery plan.
