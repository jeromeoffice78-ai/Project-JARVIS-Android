"""Chat and Voice can use the configured Groq text provider without OpenAI keys.

These tests deliberately use only fake clients and disposable test tokens.
They must never call the live AI provider or access the owner's session.
"""
import os
from types import SimpleNamespace

os.environ.setdefault("OPENAI_API_KEY", "test-openai-key")
os.environ.setdefault("JARVIS_CLIENT_TOKEN", "test-client-token")
os.environ.setdefault("JARVIS_CHAIRMAN_TOKEN", "test-chairman-token")
os.environ.setdefault("JARVIS_GOOGLE_CLIENT_ID", "test-google-client-id.apps.googleusercontent.com")
os.environ.setdefault("JARVIS_CHAIRMAN_EMAIL", "test-owner@example.com")
os.environ.setdefault("JARVIS_SESSION_SECRET", "test-session-secret-long-enough-for-isolated-tests")

from fastapi.testclient import TestClient

from app import main as api


class FakeGeneralChat:
    def __init__(self, answer="Hello. I am Jarvis."):
        self.answer = answer
        self.calls = []
        self.raise_error = False

    async def create(self, **kwargs):
        self.calls.append(kwargs)
        if self.raise_error:
            raise RuntimeError("synthetic provider outage")
        return SimpleNamespace(
            choices=[SimpleNamespace(message=SimpleNamespace(content=self.answer))]
        )


class FakeGeneralProvider:
    def __init__(self, answer="Hello. I am Jarvis."):
        self.completions = FakeGeneralChat(answer=answer)
        self.chat = SimpleNamespace(completions=self.completions)


def prepare_general_provider():
    general = FakeGeneralProvider()
    api.app.state.frontier_openai = None
    api.app.state.openai = general
    api.app.state.ai_provider = "groq-free-tier"
    api.app.state.ai_model = api.GROQ_MODEL
    return general


def test_voice_chat_uses_configured_groq_when_openai_missing():
    with TestClient(api.app) as client:
        fake = prepare_general_provider()
        response = client.post(
            "/v1/frontier/query",
            headers={"Authorization": "Bearer test-client-token"},
            json={"prompt": "Hey Jarvis, what time is it?", "mode": "reason"},
        )
        assert response.status_code == 200
        data = response.json()
        assert data["answer"] == "Hello. I am Jarvis."
        assert data["model"] == api.GROQ_MODEL
        assert data["mode"] == "reason"
        assert data["sources"] == []
        call = fake.completions.calls[0]
        assert call["model"] == api.GROQ_MODEL
        assert call["messages"][1]["content"] == "Hey Jarvis, what time is it?"
        assert "Authenticated application role: client" in call["messages"][0]["content"]
        assert "tools" not in call


def test_fallback_does_not_pretend_to_have_web_or_code_tools():
    with TestClient(api.app) as client:
        fake = prepare_general_provider()
        for mode in ("research", "code"):
            response = client.post(
                "/v1/frontier/query",
                headers={"Authorization": "Bearer test-client-token"},
                json={"prompt": "Use the special tool.", "mode": mode},
            )
            assert response.status_code == 503
        assert fake.completions.calls == []


def test_fallback_rejects_unsupported_camera_analysis():
    with TestClient(api.app) as client:
        fake = prepare_general_provider()
        response = client.post(
            "/v1/frontier/query",
            headers={"Authorization": "Bearer test-client-token"},
            json={
                "prompt": "Describe this frame.",
                "mode": "reason",
                "image_base64": "ZmFrZS1pbWFnZQ==",
            },
        )
        assert response.status_code == 503
        assert "vision provider" in response.json()["detail"]
        assert fake.completions.calls == []


def test_unconfigured_backend_does_not_claim_to_answer():
    with TestClient(api.app) as client:
        api.app.state.frontier_openai = None
        api.app.state.openai = None
        response = client.post(
            "/v1/frontier/query",
            headers={"Authorization": "Bearer test-client-token"},
            json={"prompt": "Hello Jarvis."},
        )
        assert response.status_code == 503


def test_fallback_authentication_remains_required():
    with TestClient(api.app) as client:
        fake = prepare_general_provider()
        response = client.post(
            "/v1/frontier/query",
            json={"prompt": "Protected command."},
        )
        assert response.status_code == 401
        assert fake.completions.calls == []


def test_fallback_reports_upstream_error_without_leaking_credentials():
    with TestClient(api.app) as client:
        fake = prepare_general_provider()
        fake.completions.raise_error = True
        response = client.post(
            "/v1/frontier/query",
            headers={"Authorization": "Bearer test-client-token"},
            json={"prompt": "Hello."},
        )
        assert response.status_code == 502
        assert "RuntimeError" in response.json()["detail"]
        assert "test-" not in response.json()["detail"]


def test_fallback_rejects_empty_model_answer():
    with TestClient(api.app) as client:
        fake = prepare_general_provider()
        fake.completions.answer = "   "
        response = client.post(
            "/v1/frontier/query",
            headers={"Authorization": "Bearer test-client-token"},
            json={"prompt": "Hello."},
        )
        assert response.status_code == 502
        assert "empty answer" in response.json()["detail"]
