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


def test_auth_check_rejects_missing_token():
    with TestClient(api.app) as client:
        response = client.get("/v1/auth/check")
        assert response.status_code == 401


def test_auth_check_accepts_existing_jarvis_client_token():
    with TestClient(api.app) as client:
        response = client.get(
            "/v1/auth/check",
            headers={"Authorization": "Bearer test-client-token"},
        )
        assert response.status_code == 200
        payload = response.json()
        assert payload["authenticated"] is True
        assert payload["role"] == "client"


def test_auth_check_accepts_chairman_session():
    identity = JarvisIdentity(
        subject="google-subject-auth-check",
        email="jeromeoffice78@gmail.com",
        display_name="Jerome Office",
        role="chairman",
    )
    token, _ = issue_session(identity)

    with TestClient(api.app) as client:
        response = client.get(
            "/v1/auth/check",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 200
        payload = response.json()
        assert payload["authenticated"] is True
        assert payload["role"] == "chairman"


class _FakeFrontierResponses:
    def __init__(self):
        self.calls = []

    async def create(self, **kwargs):
        self.calls.append(kwargs)
        mode = "reason"
        tools = kwargs.get("tools") or []
        if tools and tools[0].get("type") == "web_search":
            mode = "research"
        elif tools and tools[0].get("type") == "code_interpreter":
            mode = "code"

        annotation = SimpleNamespace(
            type="url_citation",
            url="https://example.com/source",
            title="Example Source",
        )
        content = SimpleNamespace(
            annotations=[annotation] if mode == "research" else []
        )
        message = SimpleNamespace(
            type="message",
            content=[content],
        )
        return SimpleNamespace(
            output_text=f"Frontier {mode} result.",
            output=[message],
        )


class _FakeImages:
    async def generate(self, **kwargs):
        assert kwargs["model"] == api.IMAGE_MODEL
        assert kwargs["size"] == "1024x1024"
        return SimpleNamespace(
            data=[SimpleNamespace(b64_json="ZmFrZS1pbWFnZQ==")]
        )


class _FakeFiles:
    def __init__(self):
        self.created = []
        self.deleted = []

    async def create(self, **kwargs):
        self.created.append(kwargs)
        return SimpleNamespace(id="file-test-123")

    async def delete(self, file_id):
        self.deleted.append(file_id)
        return SimpleNamespace(id=file_id, deleted=True)


class _FakeFrontierOpenAI:
    def __init__(self):
        self.responses = _FakeFrontierResponses()
        self.images = _FakeImages()
        self.files = _FakeFiles()

    async def close(self):
        return None


def test_frontier_reason_uses_gpt_56_sol_without_tools():
    with TestClient(api.app) as client:
        fake = _FakeFrontierOpenAI()
        api.app.state.frontier_openai = fake
        response = client.post(
            "/v1/frontier/query",
            headers={"Authorization": "Bearer test-client-token"},
            json={"prompt": "Solve this carefully.", "mode": "reason"},
        )

        assert response.status_code == 200
        payload = response.json()
        assert payload["mode"] == "reason"
        assert payload["model"] == api.FRONTIER_MODEL
        assert payload["sources"] == []
        call = fake.responses.calls[-1]
        assert call["model"] == api.FRONTIER_MODEL
        assert "tools" not in call
        assert call["reasoning"]["effort"] == "high"


def test_frontier_research_enables_web_search_and_returns_sources():
    with TestClient(api.app) as client:
        fake = _FakeFrontierOpenAI()
        api.app.state.frontier_openai = fake
        response = client.post(
            "/v1/frontier/query",
            headers={"Authorization": "Bearer test-client-token"},
            json={"prompt": "Research current information.", "mode": "research"},
        )

        assert response.status_code == 200
        payload = response.json()
        assert payload["mode"] == "research"
        assert payload["sources"][0]["url"] == "https://example.com/source"
        call = fake.responses.calls[-1]
        assert call["tools"] == [{"type": "web_search"}]
        assert call["reasoning"]["effort"] == "xhigh"


def test_frontier_code_enables_sandboxed_code_interpreter():
    with TestClient(api.app) as client:
        fake = _FakeFrontierOpenAI()
        api.app.state.frontier_openai = fake
        response = client.post(
            "/v1/frontier/query",
            headers={"Authorization": "Bearer test-client-token"},
            json={"prompt": "Use Python to solve it.", "mode": "code"},
        )

        assert response.status_code == 200
        call = fake.responses.calls[-1]
        assert call["tools"] == [
            {
                "type": "code_interpreter",
                "container": {"type": "auto"},
            }
        ]


def test_frontier_image_returns_base64_image():
    with TestClient(api.app) as client:
        api.app.state.frontier_openai = _FakeFrontierOpenAI()
        response = client.post(
            "/v1/frontier/image",
            headers={"Authorization": "Bearer test-client-token"},
            json={"prompt": "Create a blue futuristic robot."},
        )

        assert response.status_code == 200
        payload = response.json()
        assert payload["image_base64"] == "ZmFrZS1pbWFnZQ=="
        assert payload["model"] == api.IMAGE_MODEL


def test_frontier_reason_accepts_screen_image():
    with TestClient(api.app) as client:
        fake = _FakeFrontierOpenAI()
        api.app.state.frontier_openai = fake
        response = client.post(
            "/v1/frontier/query",
            headers={"Authorization": "Bearer test-client-token"},
            json={
                "prompt": "Analyze this screen.",
                "mode": "reason",
                "image_base64": "ZmFrZS1wbmc=",
            },
        )

        assert response.status_code == 200
        call = fake.responses.calls[-1]
        assert isinstance(call["input"], list)
        content = call["input"][0]["content"]
        assert content[0]["type"] == "input_text"
        assert content[1]["type"] == "input_image"
        assert content[1]["image_url"].startswith("data:image/png;base64,")


def test_frontier_file_upload_is_analyzed_and_deleted():
    with TestClient(api.app) as client:
        fake = _FakeFrontierOpenAI()
        api.app.state.frontier_openai = fake
        response = client.post(
            "/v1/frontier/file",
            headers={"Authorization": "Bearer test-client-token"},
            data={"prompt": "Summarize this document."},
            files={
                "document": (
                    "example.txt",
                    b"Important document content.",
                    "text/plain",
                )
            },
        )

        assert response.status_code == 200
        payload = response.json()
        assert payload["mode"] == "file"
        assert fake.files.created
        assert fake.files.created[-1]["purpose"] == "user_data"
        assert fake.files.deleted == ["file-test-123"]
        call = fake.responses.calls[-1]
        assert call["input"][0]["content"][0]["type"] == "input_file"
        assert call["input"][0]["content"][0]["file_id"] == "file-test-123"


class _FakeRealtimeHttpResponse:
    status_code = 200

    def json(self):
        return {
            "value": "ek_test_realtime",
            "expires_at": 9999999999,
        }


class _FakeRealtimeHttpClient:
    def __init__(self, *args, **kwargs):
        self.post_calls = []

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return False

    async def post(self, url, **kwargs):
        self.post_calls.append((url, kwargs))
        assert url == "https://api.openai.com/v1/realtime/client_secrets"
        assert kwargs["headers"]["Authorization"] == "Bearer test-openai-key"
        assert kwargs["headers"]["OpenAI-Safety-Identifier"]
        assert kwargs["json"]["session"]["model"] == api.REALTIME_MODEL
        return _FakeRealtimeHttpResponse()


def test_realtime_client_secret_proxies_ephemeral_credential(monkeypatch):
    monkeypatch.setattr(
        api.httpx,
        "AsyncClient",
        _FakeRealtimeHttpClient,
    )

    with TestClient(api.app) as client:
        response = client.post(
            "/v1/realtime/client-secret",
            headers={"Authorization": "Bearer test-client-token"},
        )

        assert response.status_code == 200
        payload = response.json()
        assert payload["value"] == "ek_test_realtime"


class _FakeMusicResponses:
    def __init__(self):
        self.calls = []

    async def create(self, **kwargs):
        self.calls.append(kwargs)
        return SimpleNamespace(
            output_text="https://www.youtube.com/watch?v=M7lc1UVf-VE",
            output=[],
        )


class _FakeMusicOpenAI:
    def __init__(self):
        self.responses = _FakeMusicResponses()

    async def close(self):
        return None


def test_music_search_returns_only_validated_youtube_result(monkeypatch):
    async def fake_validate(video_id):
        assert video_id == "M7lc1UVf-VE"
        return {
            "title": "Verified Song",
            "author": "Official Artist",
            "thumbnail_url": "https://example.com/thumb.jpg",
            "watch_url": "https://www.youtube.com/watch?v=M7lc1UVf-VE",
        }

    monkeypatch.setattr(
        api,
        "_validate_youtube_video",
        fake_validate,
    )

    with TestClient(api.app) as client:
        fake = _FakeMusicOpenAI()
        api.app.state.frontier_openai = fake

        response = client.post(
            "/v1/music/search",
            headers={"Authorization": "Bearer test-client-token"},
            json={"query": "Verified Song by Official Artist"},
        )

        assert response.status_code == 200
        payload = response.json()
        assert payload["provider"] == "youtube"
        assert payload["video_id"] == "M7lc1UVf-VE"
        assert payload["title"] == "Verified Song"
        assert payload["author"] == "Official Artist"
        assert fake.responses.calls[-1]["tools"] == [{"type": "web_search"}]


def test_youtube_video_id_parses_supported_url_shapes():
    assert (
        api._youtube_video_id(
            "https://www.youtube.com/watch?v=M7lc1UVf-VE"
        )
        == "M7lc1UVf-VE"
    )
    assert (
        api._youtube_video_id(
            "https://youtu.be/M7lc1UVf-VE"
        )
        == "M7lc1UVf-VE"
    )
    assert (
        api._youtube_video_id(
            "https://music.youtube.com/watch?v=M7lc1UVf-VE"
        )
        == "M7lc1UVf-VE"
    )
