"""Regression checks for a secure email fallback without native Google Sign-In."""
from __future__ import annotations

import asyncio
from urllib.parse import quote

import httpx
import pytest
from fastapi import HTTPException

from app import auth_email


def test_code_uses_fixed_verified_chairman_email() -> None:
    payload = auth_email.parse_challenge("123456")
    assert payload == {"email": auth_email.CHAIRMAN_EMAIL, "token": "123456", "type": "email"}


def test_unopened_magic_link_verifies_hash_not_redirect() -> None:
    token = "f" * 64
    payload = auth_email.parse_challenge(
        "https://idpneeyysraraznqmiio.supabase.co/auth/v1/verify?"
        f"token={token}&type=magiclink&redirect_to=https%3A%2F%2Fexample.com"
    )
    assert payload == {"token_hash": token, "type": "magiclink"}


@pytest.mark.parametrize("proof", [
    "https://example.com/auth/v1/verify?token=" + "f" * 64 + "&type=magiclink",
    "http://idpneeyysraraznqmiio.supabase.co/auth/v1/verify?token=" + "f" * 64 + "&type=email",
    "https://idpneeyysraraznqmiio.supabase.co.evil.invalid/auth/v1/verify?token=" + "f" * 64 + "&type=email",
    "https://idpneeyysraraznqmiio.supabase.co/auth/v1/verify?token=short&type=email",
    "https://idpneeyysraraznqmiio.supabase.co/auth/v1/verify?token=" + "f" * 64 + "&type=recovery",
    "test@example.com",
])
def test_reject_untrusted_or_malformed_challenges(proof: str) -> None:
    with pytest.raises(HTTPException) as exc:
        auth_email.parse_challenge(proof)
    assert exc.value.status_code == 422


def _response(status: int, obj: dict, path: str) -> httpx.Response:
    return httpx.Response(
        status, json=obj, request=httpx.Request("GET", "https://idpneeyysraraznqmiio.supabase.co" + path)
    )


class FakeSupabaseClient:
    last_verify: dict | None = None
    sent_to: str | None = None
    email_verified: bool = True
    claimed_email: str = auth_email.CHAIRMAN_EMAIL
    fail_verify: bool = False

    def __init__(self, *args, **kwargs) -> None:
        pass

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        return False

    async def post(self, url: str, *, headers: dict, json: dict):
        assert headers["apikey"] == "test-publishable-key"
        if url.endswith("/otp"):
            type(self).sent_to = json["email"]
            assert json["create_user"] is False
            return _response(200, {}, "/auth/v1/otp")
        type(self).last_verify = json
        if type(self).fail_verify:
            return _response(403, {}, "/auth/v1/verify")
        return _response(200, {"access_token": "a" * 200}, "/auth/v1/verify")

    async def get(self, url: str, *, headers: dict):
        assert headers["authorization"] == "Bearer " + "a" * 200
        return _response(200, {
            "id": "supabase-confirmed-owner-id",
            "email": type(self).claimed_email,
            "email_confirmed_at": "2026-09-20T14:00:00Z"
            if type(self).email_verified else None,
        }, "/auth/v1/user")


@pytest.fixture(autouse=True)
def configure_fake_supabase(monkeypatch):
    FakeSupabaseClient.last_verify = None
    FakeSupabaseClient.sent_to = None
    FakeSupabaseClient.email_verified = True
    FakeSupabaseClient.claimed_email = auth_email.CHAIRMAN_EMAIL
    FakeSupabaseClient.fail_verify = False
    monkeypatch.setattr(auth_email, "SUPABASE_PUBLIC_KEY", "test-publishable-key")
    monkeypatch.setattr(auth_email.httpx, "AsyncClient", FakeSupabaseClient)


def test_email_otp_delivered_only_to_chairman() -> None:
    asyncio.run(auth_email.send_chairman_email())
    assert FakeSupabaseClient.sent_to == auth_email.CHAIRMAN_EMAIL


def test_verified_existing_email_issues_correct_identity() -> None:
    user = asyncio.run(auth_email.verify_chairman_email("654321"))
    assert user.email == auth_email.CHAIRMAN_EMAIL
    assert user.role == "chairman"
    assert user.subject


def test_magic_link_uses_supabase_token_hash() -> None:
    user = asyncio.run(auth_email.verify_chairman_email(
        "https://idpneeyysraraznqmiio.supabase.co/auth/v1/verify?token=" + "a" * 64 + "&type=email"
    ))
    assert user.role == "chairman"
    assert FakeSupabaseClient.last_verify == {"token_hash": "a" * 64, "type": "email"}


def test_unverified_email_cannot_become_chairman() -> None:
    FakeSupabaseClient.email_verified = False
    with pytest.raises(HTTPException) as exc:
        asyncio.run(auth_email.verify_chairman_email("654321"))
    assert exc.value.status_code == 403


def test_wrong_email_cannot_become_chairman() -> None:
    FakeSupabaseClient.claimed_email = "not-chairman@example.com"
    with pytest.raises(HTTPException) as exc:
        asyncio.run(auth_email.verify_chairman_email("654321"))
    assert exc.value.status_code == 403


def test_invalid_or_used_proof_cannot_become_chairman() -> None:
    FakeSupabaseClient.fail_verify = True
    with pytest.raises(HTTPException) as exc:
        asyncio.run(auth_email.verify_chairman_email("654321"))
    assert exc.value.status_code == 422
