# Fix JARVIS Google sign-in error 10

A `PlatformException(sign_in_failed, ...ApiException: 10...)` is normally Android Google OAuth `DEVELOPER_ERROR`. It occurs before JARVIS talks to its backend.

1. Install the **permanently production-signed** release, not an old `JARVIS-AI-ASSISTANT-v1.3.apk` debug release. Back up any local-only data before uninstalling differently signed builds.
2. In the Google Cloud project containing JARVIS's Web OAuth client `498363735983-nka03bna11698m7o6aool7vnga8fb80e.apps.googleusercontent.com`, open Google Auth Platform > Clients.
3. Create or verify an **Android** OAuth client with package `com.jarvis.project_jarvis` and signing SHA-1 `39:96:F2:AD:FB:2E:E3:34:97:D7:64:C2:29:44:A8:C8:78:4F:C6:4E`.
4. Verify the Google OAuth consent screen and permitted test users if it is in Testing status. Retry JARVIS Google sign-in after credentials have propagated.
5. If using another signing certificate, register that APK's actual signer SHA-1 instead. Android release SHA-1 is printed in signed-release asset `OAUTH-ANDROID-IDENTITY.txt`.

Do **not** commit Google OAuth client secrets or signing private keys to this public repository. The Android SHA-1, package and web client identifier above are public identifiers.

Source of truth for the permanent certificate and package: `.github/workflows/publish-jarvis-signed-release.yml` and `.github/workflows/jarvis-legal-enterprise.yml`.
