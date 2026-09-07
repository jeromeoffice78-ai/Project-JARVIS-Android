from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import secrets
import time
from dataclasses import dataclass
from datetime import datetime, timezone

from fastapi import HTTPException, status
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

DEFAULT_GOOGLE_CLIENT_ID = (
    "498363735983-nka03bna11698m7o6ao0l7vnga8fb80e.apps.googleusercontent.com"
)
DEFAULT_CHAIRMAN_EMAIL = "jeromeoffice78@gmail.com"

GOOGLE_CLIENT_ID = os.getenv(
    "JARVIS_GOOGLE_CLIENT_ID", DEFAULT_GOOGLE_CLIENT_ID
).strip()
CHAIRMAN_EMAIL = os.getenv(
    "JARVIS_CHAIRMAN_EMAIL", DEFAULT_CHAIRMAN_EMAIL
).strip().lower()
CHAIRMAN_GOOGLE_SUB = os.getenv("JARVIS_CHAIRMAN_GOOGLE_SUB", "").strip()
# A configured secret survives restarts. The random fallback remains server-only and
# keeps authentication usable on a single-instance free deployment; its sessions
# intentionally expire whenever the service restarts.
SESSION_SECRET = (
    os.getenv("JARVIS_SESSION_SECRET", "").strip() or secrets.token_urlsafe(48)
)
SESSION_TTL_SECONDS = int(os.getenv("JARVIS_SESSION_TTL_SECONDS", "86400"))


@dataclass(frozen=True)
class JarvisIdentity:
    subject: str
    email: str
    display_name: str
    role: str


def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _b64url_decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def auth_ready() -> bool:
    return bool(GOOGLE_CLIENT_ID and SESSION_SECRET and (CHAIRMAN_GOOGLE_SUB or CHAIRMAN_EMAIL))


def verify_google_chairman(id_token_value: str) -> JarvisIdentity:
    if not auth_ready():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Google Chairman authentication is not configured.",
        )

    try:
        claims = google_id_token.verify_oauth2_token(
            id_token_value,
            google_requests.Request(),
            GOOGLE_CLIENT_ID,
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Google identity verification failed.",
        ) from exc

    if claims.get("email_verified") is not True:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="A verified Google email is required.",
        )

    subject = str(claims.get("sub") or "").strip()
    email = str(claims.get("email") or "").strip().lower()
    name = str(claims.get("name") or "Jerome Office").strip() or "Jerome Office"

    if not subject or not email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Google identity did not contain required claims.",
        )

    if CHAIRMAN_GOOGLE_SUB:
        authorized = hmac.compare_digest(subject, CHAIRMAN_GOOGLE_SUB)
    else:
        authorized = bool(CHAIRMAN_EMAIL) and hmac.compare_digest(email, CHAIRMAN_EMAIL)

    if not authorized:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This Google account is not authorized for Chairman access.",
        )

    return JarvisIdentity(
        subject=subject,
        email=email,
        display_name=name,
        role="chairman",
    )


def issue_session(identity: JarvisIdentity) -> tuple[str, str]:
    if not SESSION_SECRET:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="JARVIS session signing is not configured.",
        )

    now = int(time.time())
    expires = now + max(300, SESSION_TTL_SECONDS)
    payload = {
        "sub": identity.subject,
        "email": identity.email,
        "name": identity.display_name,
        "role": identity.role,
        "iat": now,
        "exp": expires,
        "iss": "jarvis-legal-enterprise",
    }
    encoded = _b64url_encode(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8"))
    signature = hmac.new(SESSION_SECRET.encode("utf-8"), encoded.encode("ascii"), hashlib.sha256).digest()
    token = f"{encoded}.{_b64url_encode(signature)}"
    expires_at = datetime.fromtimestamp(expires, tz=timezone.utc).isoformat().replace("+00:00", "Z")
    return token, expires_at


def verify_session(token: str) -> JarvisIdentity | None:
    if not token or not SESSION_SECRET:
        return None

    try:
        encoded, supplied_signature = token.split(".", 1)
        expected_signature = hmac.new(
            SESSION_SECRET.encode("utf-8"),
            encoded.encode("ascii"),
            hashlib.sha256,
        ).digest()
        if not hmac.compare_digest(_b64url_decode(supplied_signature), expected_signature):
            return None
        payload = json.loads(_b64url_decode(encoded).decode("utf-8"))
        if payload.get("iss") != "jarvis-legal-enterprise":
            return None
        if int(payload.get("exp", 0)) <= int(time.time()):
            return None
        if payload.get("role") != "chairman":
            return None

        subject = str(payload.get("sub") or "").strip()
        email = str(payload.get("email") or "").strip().lower()
        name = str(payload.get("name") or "Jerome Office").strip() or "Jerome Office"
        if not subject or not email:
            return None

        if CHAIRMAN_GOOGLE_SUB and not hmac.compare_digest(subject, CHAIRMAN_GOOGLE_SUB):
            return None
        if not CHAIRMAN_GOOGLE_SUB and CHAIRMAN_EMAIL and not hmac.compare_digest(email, CHAIRMAN_EMAIL):
            return None

        return JarvisIdentity(subject=subject, email=email, display_name=name, role="chairman")
    except Exception:
        return None
