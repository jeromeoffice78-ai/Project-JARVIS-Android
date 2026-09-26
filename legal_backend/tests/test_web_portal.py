"""The replacement Chairman web login reuses existing verified auth.

Run without sending a message or changing any Chairman account data.
"""
from __future__ import annotations

from fastapi.testclient import TestClient

from app.auth_google import JarvisIdentity
from app.main import app


client = TestClient(app)


def test_login_page_has_no_legacy_password_form() -> None:
    response = client.get("/login")
    assert response.status_code == 200
    assert "SEND VERIFICATION EMAIL" in response.text
    assert "Chairman" in response.text
    assert 'type="password"' not in response.text
    assert response.headers["cache-control"] == "no-store"
    assert "frame-ancestors 'none'" in response.headers["content-security-policy"]
    assert "connect-src 'self'" in response.headers["content-security-policy"]


def test_login_assets_do_not_expose_credentials() -> None:
    js = client.get("/login/app.js")
    css = client.get("/login/app.css")
    assert js.status_code == 200
    assert css.status_code == 200
    assert "/v1/auth/email/start" in js.text
    assert "/v1/auth/email/verify" in js.text
    assert "sessionStorage" in js.text
    assert "localStorage" not in js.text
    assert "access_token" in js.text
    assert "send verification" in client.get("/login").text.lower()


def test_email_login_routes_use_existing_chairman_verification(monkeypatch) -> None:
    import app.main as main
    sent = []

    async def fake_send():
        sent.append(True)

    async def fake_verify(proof: str) -> JarvisIdentity:
        assert proof == "123456"
        return JarvisIdentity(
            subject="test-account-subject",
            email="jeromeoffice78@gmail.com",
            display_name="Jerome Office",
            role="chairman",
        )

    monkeypatch.setattr(main, "send_chairman_email", fake_send)
    monkeypatch.setattr(main, "verify_chairman_email", fake_verify)

    started = client.post("/v1/auth/email/start")
    assert started.status_code == 200
    assert started.json()["status"] == "sent"
    assert sent == [True]

    verified = client.post("/v1/auth/email/verify", json={"proof": "123456"})
    assert verified.status_code == 200
    data = verified.json()
    assert data["role"] == "chairman"
    assert data["subscription_exempt"] is True
    assert data["access_token"]

    restored = client.get(
        "/v1/auth/session",
        headers={"Authorization": "Bearer " + data["access_token"]},
    )
    assert restored.status_code == 200
    assert restored.json()["role"] == "chairman"
