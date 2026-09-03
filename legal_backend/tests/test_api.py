import os
from types import SimpleNamespace

os.environ.setdefault("OPENAI_API_KEY", "test-openai-key")
os.environ.setdefault("JARVIS_CHAIRMAN_TOKEN", "test-chairman-token")
os.environ.setdefault("JARVIS_CLIENT_TOKEN", "test-client-token")

from fastapi.testclient import TestClient

from app import main as api


class _FakeResponses:
    async def create(self, **kwargs):
        assert kwargs["model"] == api.DEFAULT_MODEL
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


def test_chairman_query_returns_answer_and_matter_id():
    with TestClient(api.app) as client:
        api.app.state.openai = _FakeOpenAI()
        response = client.post(
            "/v1/legal/query",
            headers={"Authorization": "Bearer test-chairman-token"},
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
        assert payload["model"] == api.DEFAULT_MODEL
