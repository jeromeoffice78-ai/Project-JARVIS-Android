# JARVIS Legal Enterprise Backend

Secure FastAPI backend for the JARVIS Legal Enterprise Chairman Android app.

## API

- `GET /health` — service health and configured model name.
- `POST /v1/legal/query` — authenticated JARVIS legal analysis endpoint consumed by the Flutter app.

## Required production environment variables

- `OPENAI_API_KEY` — server-side OpenAI API credential. Never place this value in the Android app or Git repository.
- `JARVIS_CLIENT_TOKEN` — long random bearer token shared only through secure build/deployment secrets.
- `OPENAI_MODEL` — optional model override. Defaults to `gpt-5.6-sol`.

## Local run

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export OPENAI_API_KEY='...'
export JARVIS_CLIENT_TOKEN='...'
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Then set the Android build environment:

- `JARVIS_HTTP_BASE=https://your-backend.example`
- `JARVIS_CLIENT_TOKEN=<same secure client token>`

The Flutter app already sends requests to `POST /v1/legal/query`.

## Vercel

This folder includes `vercel.json`. When creating the Vercel project from GitHub, use `legal_backend` as the project Root Directory and add the required environment variables in Vercel before the production deployment.

## Security boundary

The mobile client never receives `OPENAI_API_KEY`. The backend checks a bearer token before accepting legal-query requests. For a commercial multi-user release, replace the shared build token with user authentication, server-side role/entitlement checks, per-user authorization, audit logging, rate limits, and revocation.
