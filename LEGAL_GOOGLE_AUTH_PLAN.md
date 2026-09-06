# JARVIS Legal Enterprise — Google Chairman Authentication

Implementation branch goal:

1. Google authenticates the user on Android.
2. Android sends only the Google OpenID Connect ID token to the JARVIS backend.
3. The backend verifies signature, issuer, audience, expiry, and `email_verified` using Google Auth libraries.
4. The backend maps the configured Chairman Google identity to `chairman` authority.
5. The backend issues a short-lived, HMAC-signed JARVIS session token.
6. Chairman authority and subscription exemption are enforced server-side.
7. Static Chairman bearer-token support remains temporarily available only as a migration fallback.

Required server environment variables:

- `JARVIS_GOOGLE_CLIENT_ID` — Google OAuth **Web application** client ID used as the OIDC audience.
- `JARVIS_CHAIRMAN_EMAIL` — approved Chairman Google email for initial identity binding.
- `JARVIS_CHAIRMAN_GOOGLE_SUB` — recommended immutable Google subject identifier after first verified binding.
- `JARVIS_SESSION_SECRET` — long random server-only HMAC secret.

Required Android build define:

- `GOOGLE_SERVER_CLIENT_ID` — same Web application OAuth client ID used by the backend.

No Google password, OpenAI key, session secret, or Chairman static token belongs in the APK.
