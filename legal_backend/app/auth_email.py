"""Passwordless Chairman email fallback for Android Google API error 10.

Uses the existing Supabase Auth account. Supabase validates the one-time proof;
JARVIS then independently retrieves the authenticated user before issuing the
same short-lived, signed Chairman session used by Google login. No email OTP,
magic link or access token is ever logged or returned to another client.
"""
from __future__ import annotations

import hmac
import os
import re
from urllib.parse import parse_qs, urlsplit

import httpx
from fastapi import HTTPException, status

from .auth_google import CHAIRMAN_EMAIL, CHAIRMAN_GOOGLE_SUB, JarvisIdentity

SUPABASE_URL = os.getenv(
    "JARVIS_SUPABASE_AUTH_URL", "https://idpneeyysraraznqmiio.supabase.co"
).strip().rstrip("/")
SUPABASE_PUBLIC_KEY = os.getenv("JARVIS_SUPABASE_PUBLISHABLE_KEY", "").strip()
SUPABASE_HOST = urlsplit(SUPABASE_URL).hostname
SUPPORTED_MAGIC_TYPES = frozenset({"email", "magiclink"})


def email_auth_ready() -> bool:
    return bool(SUPABASE_PUBLIC_KEY and SUPABASE_HOST and CHAIRMAN_EMAIL)


def _headers() -> dict[str, str]:
    if not email_auth_ready():
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Secure email sign-in is not configured.")
    return {
        "apikey": SUPABASE_PUBLIC_KEY,
        "content-type": "application/json",
    }


def _friendly_supabase_error(response: httpx.Response, *, sending: bool) -> HTTPException:
    if response.status_code == 429:
        return HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "Too many attempts. Wait before requesting or checking another code.",
        )
    if response.status_code in {400, 401, 403, 404, 422}:
        return HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY if not sending else status.HTTP_503_SERVICE_UNAVAILABLE,
            "The verification code or sign-in link is invalid, used, or expired."
            if not sending else "Email verification is unavailable. Please try again later.",
        )
    return HTTPException(status.HTTP_502_BAD_GATEWAY, "Email verification provider is temporarily unavailable.")


async def send_chairman_email() -> None:
    """Send only to the configured Chairman. No arbitrary email addresses."""
    headers = _headers()
    try:
        async with httpx.AsyncClient(timeout=16, follow_redirects=False) as client:
            response = await client.post(
                f"{SUPABASE_URL}/auth/v1/otp",
                headers=headers,
                json={"email": CHAIRMAN_EMAIL, "create_user": False},
            )
    except httpx.RequestError as exc:
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, "Unable to reach email verification service."
        ) from exc
    if response.status_code not in (200, 201, 204):
        raise _friendly_supabase_error(response, sending=True)


def parse_challenge(proof: str) -> dict[str, str]:
    """Accept an emailed numeric OTP or *unopened* Supabase magic link.

    Default Supabase templates contain a magic link, not the printed six-digit
    code. Pasting the unopened link into JARVIS allows this fallback to work
    without a template or redirect-URL change in the user's dashboard.
    """
    proof = proof.strip()
    if re.fullmatch(r"[0-9]{6,8}", proof):
        return {"email": CHAIRMAN_EMAIL, "token": proof, "type": "email"}
    if len(proof) > 2500 or not proof.startswith("https://"):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Paste the email code or full unused sign-in link.")
    try:
        parsed = urlsplit(proof)
        if parsed.scheme != "https" or parsed.hostname != SUPABASE_HOST or (
            parsed.port is not None and parsed.port != 443
        ):
            raise ValueError("Untrusted link host")
        if parsed.path.rstrip("/") != "/auth/v1/verify":
            raise ValueError("Unrecognized sign-in link")
        values = parse_qs(parsed.query, keep_blank_values=False)
        token = values.get("token", [""])[0]
        link_type = values.get("type", [""])[0]
        if link_type not in SUPPORTED_MAGIC_TYPES or not re.fullmatch(r"[A-Za-z0-9_-]{30,300}", token):
            raise ValueError("Invalid verification parameters")
    except (ValueError, TypeError) as exc:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY, "Paste the complete, unused Supabase email sign-in link."
        ) from exc
    return {"token_hash": token, "type": link_type}


async def verify_chairman_email(proof: str) -> JarvisIdentity:
    """Supabase verifies email possession, then JARVIS enforces Chairman ACL."""
    headers = _headers()
    challenge = parse_challenge(proof)
    try:
        async with httpx.AsyncClient(timeout=16, follow_redirects=False) as client:
            verification = await client.post(
                f"{SUPABASE_URL}/auth/v1/verify", headers=headers, json=challenge
            )
            if verification.status_code != 200:
                raise _friendly_supabase_error(verification, sending=False)
            try:
                access_token = verification.json().get("access_token", "")
            except (ValueError, AttributeError):
                access_token = ""
            if not isinstance(access_token, str) or len(access_token) < 100:
                raise HTTPException(
                    status.HTTP_401_UNAUTHORIZED, "Email verification produced no secure session."
                )
            user_response = await client.get(
                f"{SUPABASE_URL}/auth/v1/user",
                headers={**headers, "authorization": f"Bearer {access_token}"},
            )
    except httpx.RequestError as exc:
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, "Unable to reach email verification service."
        ) from exc

    if user_response.status_code != 200:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Email verification failed.")
    try:
        user = user_response.json()
    except ValueError as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid email verification response.") from exc

    if not isinstance(user, dict):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid email verification response.")
    verified_email = str(user.get("email") or "").strip().lower()
    account_id = str(user.get("id") or "").strip()
    if not account_id or not verified_email or not user.get("email_confirmed_at"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Verified email address required.")
    if not hmac.compare_digest(verified_email, CHAIRMAN_EMAIL):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "This account is not authorized for Chairman access.")

    # Maintain compatibility with deployments that also pin the Google subject.
    subject = CHAIRMAN_GOOGLE_SUB or f"supabase:{account_id}"
    return JarvisIdentity(
        subject=subject,
        email=verified_email,
        display_name="Jerome Office",
        role="chairman",
    )
