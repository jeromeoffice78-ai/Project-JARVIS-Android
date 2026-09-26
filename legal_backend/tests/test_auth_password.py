"""Supabase account sessions must never escalate an unverified email to Chairman."""
from __future__ import annotations

import asyncio

import httpx
import pytest
from fastapi import HTTPException

from app import auth_password


class FakeSupabase:
    email = auth_password.CHAIRMAN_EMAIL
    confirmed = True
    token_valid = True
    transport_error = False
    last_token = None

    def __init__(self, *args, **kwargs):
        assert kwargs["follow_redirects"] is False

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        return False

    async def get(self, url, *, headers):
        assert url == auth_password.SUPABASE_URL + "/auth/v1/user"
        assert headers["apikey"] == "test-publishable"
        type(self).last_token = headers["authorization"]
        if type(self).transport_error:
            raise httpx.ConnectError("Offline", request=httpx.Request("GET", url))
        return httpx.Response(
            200 if type(self).token_valid else 401,
            json={
                "id": "verified-id",
                "email": type(self).email,
                "email_confirmed_at": "2026-09-20T14:00:00Z"
                if type(self).confirmed else None,
            },
            request=httpx.Request("GET", url),
        )


@pytest.fixture(autouse=True)
def fake_http(monkeypatch):
    FakeSupabase.email = auth_password.CHAIRMAN_EMAIL
    FakeSupabase.confirmed = True
    FakeSupabase.token_valid = True
    FakeSupabase.transport_error = False
    FakeSupabase.last_token = None
    monkeypatch.setattr(
        auth_password,
        "_headers",
        lambda: {"apikey": "test-publishable", "content-type": "application/json"},
    )
    monkeypatch.setattr(auth_password.httpx, "AsyncClient", FakeSupabase)


def test_verified_owner_gets_chairman_session_identity():
    identity = asyncio.run(auth_password.verify_password_account("a" * 240))
    assert identity.role == "chairman"
    assert identity.email == auth_password.CHAIRMAN_EMAIL
    assert identity.subject.startswith("supabase:") or identity.subject
    assert FakeSupabase.last_token == "Bearer " + "a" * 240


def test_unverified_email_cannot_get_owner_access():
    FakeSupabase.confirmed = False
    with pytest.raises(HTTPException) as exc:
        asyncio.run(auth_password.verify_password_account("a" * 240))
    assert exc.value.status_code == 403


def test_unapproved_email_cannot_get_owner_access():
    FakeSupabase.email = "attacker@example.org"
    with pytest.raises(HTTPException) as exc:
        asyncio.run(auth_password.verify_password_account("a" * 240))
    assert exc.value.status_code == 403


def test_invalid_supabase_session_is_rejected():
    FakeSupabase.token_valid = False
    with pytest.raises(HTTPException) as exc:
        asyncio.run(auth_password.verify_password_account("a" * 240))
    assert exc.value.status_code == 401


def test_empty_session_is_rejected():
    with pytest.raises(HTTPException) as exc:
        asyncio.run(auth_password.verify_password_account(""))
    assert exc.value.status_code == 401


def test_provider_outage_does_not_allow_access():
    FakeSupabase.transport_error = True
    with pytest.raises(HTTPException) as exc:
        asyncio.run(auth_password.verify_password_account("a" * 240))
    assert exc.value.status_code == 502
