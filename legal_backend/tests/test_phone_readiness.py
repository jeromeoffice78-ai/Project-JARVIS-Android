"""Voice-provider status must not imply Android call-control means spoken reception."""
import asyncio
from app import main as api


def _status():
    return asyncio.run(api.phone_receptionist_status("chairman"))


def test_cloud_service_unconfigured_with_no_verified_provider(monkeypatch):
    monkeypatch.delenv("VAPI_API_KEY", raising=False)
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.delenv("JARVIS_PHONE_SIP_ROUTE_VERIFIED", raising=False)
    monkeypatch.setattr(api, "PHONE_WEBHOOK_SECRET", "")
    monkeypatch.setattr(api, "RECEPTIONIST_NUMBER", "")
    status = _status()
    assert status.configured is False
    assert status.phone_number == ""
    assert "default phone app" in status.detail


def test_vapi_without_assigned_phone_is_not_reported_ready(monkeypatch):
    monkeypatch.setenv("VAPI_API_KEY", "test-token")
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    async def no_phone():
        return None
    monkeypatch.setattr(api, "_vapi_bind_existing_phone", no_phone)
    status = _status()
    assert status.configured is False
    assert "no assigned" in status.detail


def test_verified_vapi_number_is_ready(monkeypatch):
    monkeypatch.setenv("VAPI_API_KEY", "test-token")
    async def connected():
        return {"phone": {"number": "+15555550100", "id": "phone_1"}}
    monkeypatch.setattr(api, "_vapi_bind_existing_phone", connected)
    status = _status()
    assert status.configured is True
    assert status.provider == "vapi"
    assert status.phone_number == "+15555550100"


def test_sip_requires_verified_route_not_only_api_keys(monkeypatch):
    monkeypatch.delenv("VAPI_API_KEY", raising=False)
    monkeypatch.setenv("OPENAI_API_KEY", "test-token")
    monkeypatch.setattr(api, "PHONE_WEBHOOK_SECRET", "webhook-test")
    monkeypatch.setattr(api, "RECEPTIONIST_NUMBER", "+15555550100")
    monkeypatch.delenv("JARVIS_PHONE_SIP_ROUTE_VERIFIED", raising=False)
    assert _status().configured is False
    monkeypatch.setenv("JARVIS_PHONE_SIP_ROUTE_VERIFIED", "true")
    assert _status().configured is True


def test_vapi_status_reads_existing_assignment_without_mutating(monkeypatch):
    async def fake_request(method, path, payload=None):
        assert method == "GET"
        assert payload is None
        if path == "/phone-number":
            return [{"id": "phone_1", "number": "+15318679252", "assistantId": "assistant_1"}]
        assert path == "/assistant/assistant_1"
        return {"id": "assistant_1", "name": "JARVIS Phone Receptionist"}

    monkeypatch.setattr(api, "_vapi_request", fake_request)
    assert asyncio.run(api._vapi_bind_existing_phone())["phone"]["id"] == "phone_1"


def test_vapi_structured_message_reads_named_result():
    message = api._vapi_message_from_call({
        "id": "call_1", "customer": {"number": "+15551234567"},
        "artifact": {"structuredOutputs": {"output_1": {
            "name": "jarvis_call_message", "result": {
                "callerName": "Marcus", "callbackNumber": "+15551234567",
                "summary": "Needs a return call", "message": "Call before noon",
                "urgent": False,
            },
        }}},
    })
    assert message["caller_name"] == "Marcus"
    assert message["summary"] == "Needs a return call"
    assert message["transcript"] == "Call before noon"
    assert message["urgent"] is False
