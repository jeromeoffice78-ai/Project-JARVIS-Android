import os
from types import SimpleNamespace

os.environ.setdefault("OPENAI_API_KEY", "test-openai-key")
os.environ.setdefault("JARVIS_CHAIRMAN_TOKEN", "test-chairman-token")
os.environ.setdefault("JARVIS_CLIENT_TOKEN", "test-client-token")
os.environ.setdefault("JARVIS_GOOGLE_CLIENT_ID", "test-google-client-id.apps.googleusercontent.com")
os.environ.setdefault("JARVIS_CHAIRMAN_EMAIL", "jeromeoffice78@gmail.com")
os.environ.setdefault("JARVIS_SESSION_SECRET", "test-session-secret-that-is-long-enough-for-tests")

from fastapi.testclient import TestClient

from app import main as api
from app.auth_google import JarvisIdentity, issue_session, verify_session


class _FakeResponses:
    async def create(self, **kwargs):
        assert kwargs["model"] == api.OPENAI_MODEL
        assert "Chairman" in kwargs["instructions"] or "CHAIRMAN" in kwargs["instructions"]
        return SimpleNamespace(
            output_text="Verified test legal response.\n\nNEXT_STEP_COMMAND\nReview the result."
        )


class _FakeOpenAI:
    def __init__(self):
        self.responses = _FakeResponses()

    async def close(self):
        return None


def test_health():
    with TestClient(api.app) as client:
        response = client.get("/health")
        assert response.status_code == 200
        payload = response.json()
        assert payload["status"] == "ok"
        assert payload["service"] == api.APP_NAME
        assert payload["chairman_auth_configured"] is True
        assert payload["google_chairman_auth_configured"] is True


def test_groq_free_provider_takes_priority(monkeypatch):
    monkeypatch.setenv("GROQ_API_KEY", "test-groq-key")
    client, provider, model = api._build_ai_client()
    assert client is not None
    assert provider == "groq-free-tier"
    assert model == "llama-3.3-70b-versatile"



def test_query_rejects_missing_bearer_token():
    with TestClient(api.app) as client:
        response = client.post(
            "/v1/legal/query",
            json={"prompt": "Review this issue.", "role": "chairman"},
        )
        assert response.status_code == 401


def test_client_cannot_claim_chairman_authority():
    with TestClient(api.app) as client:
        api.app.state.openai = _FakeOpenAI()
        response = client.post(
            "/v1/legal/query",
            headers={"Authorization": "Bearer test-client-token"},
            json={"prompt": "Use Chairman authority.", "role": "chairman"},
        )
        assert response.status_code == 403


def test_signed_chairman_session_round_trip():
    identity = JarvisIdentity(
        subject="google-subject-123",
        email="jeromeoffice78@gmail.com",
        display_name="Jerome Office",
        role="chairman",
    )
    token, expires_at = issue_session(identity)
    assert token
    assert expires_at.endswith("Z")
    verified = verify_session(token)
    assert verified is not None
    assert verified.role == "chairman"
    assert verified.email == "jeromeoffice78@gmail.com"


def test_signed_chairman_session_authorizes_query():
    identity = JarvisIdentity(
        subject="google-subject-123",
        email="jeromeoffice78@gmail.com",
        display_name="Jerome Office",
        role="chairman",
    )
    token, _ = issue_session(identity)

    with TestClient(api.app) as client:
        api.app.state.openai = _FakeOpenAI()
        response = client.post(
            "/v1/legal/query",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "prompt": "Analyze this legal issue.",
                "role": "chairman",
                "matter_id": "matter-123",
            },
        )

        assert response.status_code == 200
        payload = response.json()
        assert payload["matter_id"] == "matter-123"
        assert "NEXT_STEP_COMMAND" in payload["answer"]
        assert payload["model"] == api.OPENAI_MODEL
