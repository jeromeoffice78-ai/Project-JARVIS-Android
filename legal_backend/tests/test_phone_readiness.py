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
