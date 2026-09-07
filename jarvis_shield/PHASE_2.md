# JARVIS Shield Phase 2 — Defensive Security Engine

## Status
Phase 2 implements the first real on-device security scan for the REVVL Tab 2 and other Android 9+ devices.

## Implemented checks

The scanner uses documented Android package and settings APIs to inspect:

- Installed application inventory.
- Installer/source information, including likely sideloaded packages.
- Granted phone, SMS, call-log, microphone, camera, location, contacts, calendar, media, and sensor capabilities.
- Declared and enabled Accessibility services.
- Declared and enabled notification-listener services.
- Declared and active device-administrator components.
- Apps that declare or appear to hold draw-over-other-apps access.
- Apps that declare or appear to hold unknown-app installation access.
- App target SDK and debuggable-state indicators.
- Signing-certificate SHA-256 fingerprints.
- Base-APK SHA-256 fingerprints for user apps that cross the review threshold.

## Risk engine

Risk scoring is deterministic and local. Individual permissions are not treated as proof of malware. Higher severity requires stronger privileged access or combinations that are frequently abused by banking trojans, stalkerware, remote-control scams, credential overlays, and dropper apps.

Current severity thresholds:

- LOW: score below 30.
- MEDIUM: 30–54.
- HIGH: 55–79.
- CRITICAL: 80–100.

Only applications scoring 15 or more are shown in the review list. System apps receive reduced weights for privileged services to reduce false positives, but active privileged access is still surfaced for review.

## Remediation

JARVIS Shield never bypasses Android security controls. From each finding the user can open the appropriate protected Android screen for:

- App details.
- App uninstall confirmation.
- Accessibility access review.
- Notification-listener access review.
- Device-administrator review.
- Overlay/special-access review.
- Unknown-app installation review.

## Security boundary

A normal Android application cannot silently delete arbitrary apps, inspect every other app's private sandbox, guarantee detection of zero-day malware, or reliably determine every special permission on every OEM build. JARVIS Shield therefore reports evidence and risk indicators instead of claiming that a heuristic match proves infection.

The scanner does not root the tablet, exploit the operating system, disable Android protections, or transmit the inventory to a cloud service.

## Phase 2 architecture

- `domain/model/SecurityModels.kt` — immutable scan/result/remediation models.
- `domain/security/RiskEngine.kt` — pure deterministic risk scoring.
- `data/scanner/AndroidSecurityScanner.kt` — Android package and protected-setting inspection.
- `domain/usecase/RunSecurityScanUseCase.kt` — scan orchestration boundary.
- `data/ShieldRepositoryImpl.kt` — scanner execution and Room scan-history persistence.
- `ui/ShieldViewModel.kt` — MVVM state and scan lifecycle.
- `ui/ShieldScreen.kt` — Material 3 tablet UI.
- `platform/RemediationLauncher.kt` — user-approved Android remediation navigation.
- `RiskEngineTest.kt` — unit coverage for critical risk combinations and false-positive control.

## Next phase

Phase 3 is CI/CD and build automation: Gradle wrapper verification, unit tests, Android lint, debug APK generation, signed release bundle workflow, artifact checksums, and repository-secret wiring for production signing.
