# JARVIS Legal Enterprise Backend

Secure FastAPI backend for the JARVIS Legal Enterprise Chairman Android app.

## API

- `GET /health` — service health, configured model, AI readiness, and authentication readiness.
- `POST /v1/legal/query` — authenticated JARVIS legal analysis endpoint consumed by the Flutter app.

## Required production environment variables

- `OPENAI_API_KEY` — server-side OpenAI API credential. Never place this value in the Android app or Git repository.
- `JARVIS_CHAIRMAN_TOKEN` — long random bearer credential reserved for the Chairman/owner build.
- `JARVIS_CLIENT_TOKEN` — optional separate credential for controlled client-tier testing. It cannot claim Chairman authority.
- `OPENAI_MODEL` — optional model override. Defaults to `gpt-5.6-sol`.

## Chairman security model

The backend derives authority from the bearer credential, not from the `role` string supplied by the mobile client. A request authenticated with the client credential receives client authority even if it sends `role=chairman`; that escalation attempt is rejected with HTTP 403.

The production Chairman Android build should receive the value of `JARVIS_CHAIRMAN_TOKEN` through its secure GitHub build secret. The existing Flutter transport environment variable is currently named `JARVIS_CLIENT_TOKEN`; for the Chairman build, set that build secret to the Chairman credential. The name is a transport/config compatibility detail and does not determine server authority.

## Local run

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export OPENAI_API_KEY='...'
export JARVIS_CHAIRMAN_TOKEN='...'
export JARVIS_CLIENT_TOKEN='...'
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Then set the Chairman Android build environment:

- `JARVIS_HTTP_BASE=https://your-backend.example`
- `JARVIS_CLIENT_TOKEN=<value matching the server JARVIS_CHAIRMAN_TOKEN>`

The Flutter app sends requests to `POST /v1/legal/query`.

## Vercel

This folder includes `vercel.json`. When creating the Vercel project from GitHub, use `legal_backend` as the project Root Directory and add the required environment variables in Vercel before the production deployment.

The service starts cleanly even if `OPENAI_API_KEY` is temporarily absent. `/health` remains available and reports `ai_configured=false`; AI query requests fail closed with HTTP 503 until the credential is configured.

## Security boundary

The mobile client never receives `OPENAI_API_KEY`. Chairman and client credentials are distinct, and the server prevents a client credential from escalating itself to Chairman authority. For a commercial multi-user release, replace the client shared credential with user authentication, subscription/entitlement checks, per-user authorization, audit logging, rate limits, and revocation. Chairman access remains owner-controlled and subscription-exempt.
