"""Verify a Supabase email/password session before issuing a JARVIS session.

The Android app never supplies an owner role. Supabase validates the password,
and this server independently fetches the verified identity and enforces the
existing owner allowlist. A newly registered unrelated email receives no
access to Chairman-only data or device commands.
"""
from __future__ import annotations

import hmac

import httpx
from fastapi import HTTPException, status

from .auth_email import SUPABASE_URL, _headers
from .auth_google import CHAIRMAN_EMAIL, CHAIRMAN_GOOGLE_SUB, JarvisIdentity


async def verify_password_account(access_token: str) -> JarvisIdentity:
    token = access_token.strip()
    if not token or len(token) > 10_000:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid sign-in session.")

    headers = {
        **_headers(),
        "authorization": f"Bearer {token}",
    }
    try:
        async with httpx.AsyncClient(timeout=16, follow_redirects=False) as client:
            response = await client.get(
                f"{SUPABASE_URL}/auth/v1/user", headers=headers
            )
    except httpx.RequestError as exc:
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            "Unable to verify the sign-in session right now.",
        ) from exc
    if response.status_code != 200:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            "The sign-in session is invalid or expired.",
        )
    try:
        user = response.json()
    except ValueError as exc:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            "Unable to verify the account.",
        ) from exc
    if not isinstance(user, dict):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid account.")
    account_id = str(user.get("id") or "").strip()
    email = str(user.get("email") or "").strip().lower()
    email_verified = user.get("email_confirmed_at")
    if not account_id or not email or not email_verified:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "Verify your email address before signing in.",
        )
    if not CHAIRMAN_EMAIL or not hmac.compare_digest(email, CHAIRMAN_EMAIL):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "This account is not approved for JARVIS owner access.",
        )

    subject = CHAIRMAN_GOOGLE_SUB or f"supabase:{account_id}"
    return JarvisIdentity(
        subject=subject,
        email=email,
        display_name="Jerome Office",
        role="chairman",
    )
