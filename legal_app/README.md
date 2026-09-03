# JARVIS Legal Enterprise — Chairman Edition

A dedicated Flutter Android command center for the JARVIS Legal Enterprise.

## Chairman entitlement

`JARVIS_ROLE=chairman` receives permanent full access with no subscription requirement. Customer/client roles can be gated by subscription status in commercial builds. The Chairman APK built by GitHub Actions sets the role to `chairman` and does not require Stripe to launch or use local legal-enterprise features.

## Included in the today-build MVP

- Chairman command center
- Seven-member board: Jerome Office + six AI board seats
- Five legal managing directors and automatic issue routing
- Secure local matter storage through `flutter_secure_storage`
- Matter intake, jurisdiction, status, director assignment, and deletion
- Offline director brief generation
- Optional live JARVIS legal API handoff using `JARVIS_HTTP_BASE`
- No OpenAI key embedded in the APK

## Build

The repository workflow `jarvis-legal-enterprise.yml` creates a clean Flutter Android project, overlays this source, analyzes it, builds the Chairman debug APK, and uploads the APK as a GitHub Actions artifact.

## Production note

For a commercial client release, enforce role and subscription entitlements server-side. The Chairman Edition is the owner/admin build and is intentionally subscription-exempt.
