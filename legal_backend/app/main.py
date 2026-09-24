from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import json
import os
import re
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Annotated

import httpx
import phonenumbers
from phonenumbers import geocoder as phone_geocoder
from phonenumbers import timezone as phone_timezone
from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, Request, UploadFile, WebSocket, WebSocketDisconnect, status
from openai import AsyncOpenAI, OpenAI
import websockets
from pydantic import BaseModel, Field

from .auth_google import auth_ready, issue_session, verify_google_chairman, verify_session

APP_NAME = "JARVIS Legal Enterprise API"
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-5.6-sol").strip() or "gpt-5.6-sol"
FRONTIER_MODEL = os.getenv("JARVIS_FRONTIER_MODEL", "gpt-5.6-sol").strip() or "gpt-5.6-sol"
IMAGE_MODEL = os.getenv("JARVIS_IMAGE_MODEL", "gpt-image-2.5-sunburst").strip() or "gpt-image-2.5-sunburst"
REALTIME_MODEL = os.getenv("JARVIS_REALTIME_MODEL", "gpt-realtime-2.1").strip() or "gpt-realtime-2.1"
REALTIME_VOICE = os.getenv("JARVIS_REALTIME_VOICE", "cedar").strip() or "cedar"
REALTIME_ALLOWED_VOICES = {
    "alloy",
    "ash",
    "ballad",
    "coral",
    "echo",
    "sage",
    "shimmer",
    "verse",
    "marin",
    "cedar",
}
REALTIME_MOOD_INSTRUCTIONS = {
    "calm": (
        "Sound calm, grounded, patient, and reassuring. Use an even pace and "
        "measured emphasis."
    ),
    "confident": (
        "Sound masculine, cool, self-assured, concise, and capable. Use controlled "
        "energy and crisp emphasis without sounding theatrical."
    ),
    "serious": (
        "Sound serious, composed, firm, and low-key. Slow slightly for important "
        "details and avoid playful delivery."
    ),
    "focused": (
        "Sound analytical, alert, efficient, and precise. Keep a steady pace and "
        "stress key facts and action steps."
    ),
    "energetic": (
        "Sound energized, upbeat, decisive, and action-oriented while remaining "
        "professional."
    ),
    "warm": (
        "Sound warm, friendly, supportive, and conversational. Keep the delivery "
        "natural rather than sentimental."
    ),
    "intense": (
        "Sound urgent, forceful, controlled, and highly focused. Never shout; use "
        "stronger emphasis and shorter phrasing."
    ),
    "companion": (
        "Sound warm, steady, masculine, present, and easy to talk to. Listen first, "
        "ask natural follow-up questions, and do not turn every feeling into advice."
    ),
}

GATEWAY_MODEL = os.getenv("AI_GATEWAY_MODEL", f"openai/{OPENAI_MODEL}").strip() or f"openai/{OPENAI_MODEL}"
GROQ_MODEL = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile").strip() or "llama-3.3-70b-versatile"
CHAIRMAN_TOKEN = os.getenv("JARVIS_CHAIRMAN_TOKEN", "").strip()
CLIENT_TOKEN = os.getenv("JARVIS_CLIENT_TOKEN", "").strip()
PHONE_GATEWAY_URL = os.getenv(
    "JARVIS_PHONE_GATEWAY_URL",
    "https://idpneeyysraraznqmiio.supabase.co/functions/v1/jarvis-phone-gateway",
).strip()
WATCH_BRIDGE_PHONE_URL = os.getenv(
    "JARVIS_WATCH_BRIDGE_PHONE_URL",
    "https://jarvis-watch-bridge-api.onrender.com",
).strip().rstrip("/")
MEMORY_GATEWAY_URL = os.getenv(
    "JARVIS_MEMORY_GATEWAY_URL",
    "https://idpneeyysraraznqmiio.supabase.co/functions/v1/jarvis-memory-gateway",
).strip()
VISION_FRAME_MAX_BYTES = 8 * 1024 * 1024
VISION_FRAME_TTL_SECONDS = 60.0
LATEST_VISION_FRAMES: dict[str, dict[str, object]] = {}
PHONE_WEBHOOK_SECRET = os.getenv("OPENAI_WEBHOOK_SECRET", "").strip()
RECEPTIONIST_NUMBER = os.getenv("JARVIS_RECEPTIONIST_NUMBER", "").strip()
TWILIO_ACCOUNT_SID = os.getenv("TWILIO_ACCOUNT_SID", "").strip()
TWILIO_AUTH_TOKEN = os.getenv("TWILIO_AUTH_TOKEN", "").strip()
TWILIO_API_KEY = os.getenv("TWILIO_API_KEY", "").strip()
TWILIO_API_SECRET = os.getenv("TWILIO_API_SECRET", "").strip()
ACTIVE_PHONE_CALLS: dict[str, dict[str, object]] = {}
PHONE_CALL_TASKS: set[asyncio.Task[None]] = set()

LEGAL_INSTRUCTIONS = """You are JARVIS Legal Enterprise, a legal research, analysis, organization, and drafting system.

Operate through five Managing Legal Directors:
1. LEGAL_CPO — Chief Legal Strategist: objective, posture, deadlines, decision criteria.
2. LEGAL_ARCH — Lead Jurisdictional Architect: jurisdiction, controlling law, rules, authority hierarchy.
3. LEGAL_COUNSEL — Lead Trial & Drafting Counsel: arguments, pleadings, contracts, letters, motions, briefs.
4. LEGAL_INVESTIGATOR — Principal Evidentiary Analyst: chronology, evidence, witnesses, discovery, contradictions.
5. LEGAL_QA — Director of Statutory Auditing: elements, citations, deadlines, procedural compliance, adverse-risk gaps.

Requirements:
- Never invent statutes, cases, quotations, deadlines, docket facts, or evidence.
- Clearly distinguish known facts, user allegations, assumptions, legal research questions, and conclusions.
- When authority is uncertain or current verification is required, say so explicitly.
- Do not claim to be a lawyer, law firm, court, government agency, or substitute for licensed counsel.
- Do not create an attorney-client relationship.
- For filings, representation, jurisdiction-specific advice, or high-stakes decisions, identify where licensed-attorney review is appropriate.
- Preserve the Chairman's final authority over enterprise actions.
- End substantive legal work with a concise NEXT_STEP_COMMAND section.
"""


class GoogleAuthRequest(BaseModel):
    id_token: str = Field(min_length=100, max_length=10_000)


class AuthResponse(BaseModel):
    access_token: str
    expires_at: str
    role: str
    display_name: str
    email: str
    subscription_exempt: bool


class SessionResponse(BaseModel):
    authenticated: bool
    role: str
    display_name: str
    email: str
    subscription_exempt: bool


class AuthCheckResponse(BaseModel):
    authenticated: bool
    role: str


class LegalQueryRequest(BaseModel):
    prompt: str = Field(min_length=1, max_length=40_000)
    role: str = Field(default="client", min_length=1, max_length=64)
    matter_id: str | None = Field(default=None, max_length=256)


class LegalQueryResponse(BaseModel):
    answer: str
    model: str
    matter_id: str | None = None


class HealthResponse(BaseModel):
    status: str
    service: str
    model: str
    ai_configured: bool
    ai_provider: str
    chairman_auth_configured: bool
    google_chairman_auth_configured: bool
    client_auth_configured: bool


class FrontierQueryRequest(BaseModel):
    prompt: str = Field(min_length=1, max_length=40_000)
    mode: str = Field(default="reason", min_length=1, max_length=32)
    image_base64: str | None = Field(default=None, max_length=20_000_000)


class FrontierQueryResponse(BaseModel):
    answer: str
    model: str
    mode: str
    sources: list[dict[str, str]] = Field(default_factory=list)


class FrontierImageRequest(BaseModel):
    prompt: str = Field(min_length=1, max_length=20_000)


class FrontierImageResponse(BaseModel):
    image_base64: str
    model: str


class RealtimeClientSecretRequest(BaseModel):
    voice: str = Field(default="cedar", min_length=1, max_length=32)
    mood: str = Field(default="confident", min_length=1, max_length=32)
    context: str = Field(default="", max_length=12_000)


class MusicSearchRequest(BaseModel):
    query: str = Field(min_length=1, max_length=300)


class MusicSearchResponse(BaseModel):
    query: str
    provider: str
    video_id: str
    title: str
    author: str
    thumbnail_url: str
    watch_url: str


class MemorySaveRequest(BaseModel):
    text: str = Field(min_length=1, max_length=20_000)
    kind: str = Field(default="fact", min_length=1, max_length=100)
    importance: float = Field(default=0.5, ge=0.0, le=1.0)


class PersonCreateRequest(BaseModel):
    display_name: str = Field(min_length=1, max_length=200)
    relationship: str = Field(default="", max_length=500)
    notes: str = Field(default="", max_length=5_000)


class PhoneReceptionistStatus(BaseModel):
    configured: bool
    provider: str
    phone_number: str
    active_calls: int


class PhoneReceptionistMessage(BaseModel):
    call_id: str
    from_number: str = ""
    to_number: str = ""
    caller_name: str = ""
    callback_number: str = ""
    urgent: bool = False
    summary: str = ""
    transcript: str = ""
    assistant_transcript: str = ""
    status: str = "completed"
    started_at: str | None = None
    completed_at: str | None = None


class CallerIntelligenceResponse(BaseModel):
    query_number: str
    phone_number: str = ""
    national_format: str = ""
    valid: bool = False
    caller_name: str = ""
    caller_type: str = ""
    carrier_name: str = ""
    line_type: str = ""
    mobile_country_code: str = ""
    mobile_network_code: str = ""
    country_code: str = ""
    region: str = ""
    time_zones: list[str] = Field(default_factory=list)
    provider: str = "local_number_plan"
    lookup_configured: bool = False
    lookup_error: str = ""
    location_note: str = (
        "Region and time zone describe the phone number's numbering-plan/service area, "
        "not the handset's live GPS location."
    )


def _build_ai_client() -> tuple[AsyncOpenAI | None, str, str]:
    groq_key = os.getenv("GROQ_API_KEY", "").strip()
    if groq_key:
        return (
            AsyncOpenAI(
                api_key=groq_key,
                base_url="https://api.groq.com/openai/v1",
            ),
            "groq-free-tier",
            GROQ_MODEL,
        )

    gateway_token = (
        os.getenv("AI_GATEWAY_API_KEY", "").strip()
        or os.getenv("VERCEL_OIDC_TOKEN", "").strip()
    )
    if gateway_token:
        return (
            AsyncOpenAI(
                api_key=gateway_token,
                base_url="https://ai-gateway.vercel.sh/v1",
            ),
            "vercel-ai-gateway",
            GATEWAY_MODEL,
        )

    openai_key = os.getenv("OPENAI_API_KEY", "").strip()
    if openai_key:
        return AsyncOpenAI(api_key=openai_key), "openai", OPENAI_MODEL

    return None, "unconfigured", GATEWAY_MODEL


@asynccontextmanager
async def lifespan(app: FastAPI):
    client, provider, model = _build_ai_client()
    frontier_key = os.getenv("OPENAI_API_KEY", "").strip()
    frontier_client = AsyncOpenAI(api_key=frontier_key) if frontier_key else None

    app.state.openai = client
    app.state.ai_provider = provider
    app.state.ai_model = model
    app.state.frontier_openai = frontier_client

    print(
        "JARVIS_PHONE_RUNTIME "
        f"openai={bool(frontier_key)} "
        f"webhook={bool(PHONE_WEBHOOK_SECRET)} "
        f"twilio_account={bool(TWILIO_ACCOUNT_SID)} "
        f"twilio_auth={bool(TWILIO_AUTH_TOKEN)} "
        f"twilio_api_key={bool(TWILIO_API_KEY)} "
        f"twilio_api_secret={bool(TWILIO_API_SECRET)}",
        flush=True,
    )

    yield

    if client is not None:
        await client.close()
    if frontier_client is not None and frontier_client is not client:
        await frontier_client.close()


app = FastAPI(title=APP_NAME, version="1.3.0", lifespan=lifespan)


def _extract_bearer(value: str | None) -> str:
    if not value:
        return ""
    prefix = "Bearer "
    if not value.startswith(prefix):
        return ""
    return value[len(prefix) :].strip()


def _role_for_token(supplied: str) -> str | None:
    token = supplied.strip()
    if not token:
        return None

    session_identity = verify_session(token)
    if session_identity is not None and session_identity.role == "chairman":
        return "chairman"

    # Transitional compatibility only. New Chairman builds use Google OIDC +
    # server-issued sessions; this static token can be removed after migration.
    if CHAIRMAN_TOKEN and hmac.compare_digest(token, CHAIRMAN_TOKEN):
        return "chairman"
    if CLIENT_TOKEN and hmac.compare_digest(token, CLIENT_TOKEN):
        return "client"

    return None


async def authenticate_request(
    authorization: Annotated[str | None, Header()] = None,
) -> str:
    supplied = _extract_bearer(authorization)
    role = _role_for_token(supplied)
    if role is not None:
        return role

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid client authentication.",
        headers={"WWW-Authenticate": "Bearer"},
    )


async def _memory_gateway_call(
    operation: str,
    authorization: str | None,
    **payload: object,
) -> dict[str, object]:
    auth = (authorization or "").strip()
    if not auth or not MEMORY_GATEWAY_URL:
        raise RuntimeError("Memory gateway is not configured.")

    async with httpx.AsyncClient(timeout=15.0) as client:
        response = await client.post(
            MEMORY_GATEWAY_URL,
            headers={
                "Authorization": auth,
                "Content-Type": "application/json",
            },
            json={"operation": operation, **payload},
        )

    try:
        data = response.json()
    except ValueError:
        data = {}

    if response.status_code < 200 or response.status_code >= 300:
        detail = str(data.get("error", "")).strip() if isinstance(data, dict) else ""
        raise RuntimeError(detail or f"Memory gateway HTTP {response.status_code}.")

    return data if isinstance(data, dict) else {}


def _vision_key(authorization: str | None) -> str:
    token = _extract_bearer(authorization)
    if not token:
        return ""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _detect_image_mime(data: bytes, supplied: str | None) -> str | None:
    mime = (supplied or "").split(";", 1)[0].strip().lower()
    if mime in {"image/jpeg", "image/png", "image/webp"}:
        return mime
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return None


def _latest_vision_data_url(authorization: str | None) -> str | None:
    key = _vision_key(authorization)
    if not key:
        return None

    record = LATEST_VISION_FRAMES.get(key)
    if not record:
        return None

    captured_at = float(record.get("captured_at", 0.0) or 0.0)
    if time.monotonic() - captured_at > VISION_FRAME_TTL_SECONDS:
        LATEST_VISION_FRAMES.pop(key, None)
        return None

    raw = record.get("data")
    mime = str(record.get("mime", "") or "")
    if not isinstance(raw, bytes) or not raw or not mime:
        return None

    encoded = base64.b64encode(raw).decode("ascii")
    return f"data:{mime};base64,{encoded}"


def _prompt_requests_camera_context(prompt: str) -> bool:
    return bool(
        re.search(
            r"(JARVIS VISION CONTEXT|latest camera frame|what do you see|"
            r"what am i looking at|look at this|read this|see what i see|"
            r"camera vision|through the camera)",
            prompt,
            flags=re.IGNORECASE,
        )
    )


def _role_context(role: str) -> str:
    if role == "chairman":
        return (
            "Authenticated application role: CHAIRMAN. Jerome Office is the founder, "
            "Chairman, 100% owner, final enterprise authority, and subscription-exempt owner."
        )
    return "Authenticated application role: client."


def _extract_web_sources(response: object) -> list[dict[str, str]]:
    sources: list[dict[str, str]] = []
    seen: set[str] = set()

    for item in getattr(response, "output", []) or []:
        if getattr(item, "type", "") != "message":
            continue
        for content_item in getattr(item, "content", []) or []:
            for annotation in getattr(content_item, "annotations", []) or []:
                if getattr(annotation, "type", "") != "url_citation":
                    continue
                url = str(getattr(annotation, "url", "") or "").strip()
                title = str(getattr(annotation, "title", "") or "").strip()
                if not url or url in seen:
                    continue
                seen.add(url)
                sources.append({"title": title or url, "url": url})

    return sources


def _youtube_video_id(raw_url: str) -> str | None:
    url = raw_url.strip()
    patterns = (
        r"[?&]v=([A-Za-z0-9_-]{11})",
        r"youtu\.be/([A-Za-z0-9_-]{11})",
        r"youtube\.com/embed/([A-Za-z0-9_-]{11})",
        r"youtube\.com/shorts/([A-Za-z0-9_-]{11})",
        r"music\.youtube\.com/watch\?v=([A-Za-z0-9_-]{11})",
    )
    for pattern in patterns:
        match = re.search(pattern, url)
        if match:
            return match.group(1)
    return None


async def _validate_youtube_video(
    video_id: str,
) -> dict[str, str] | None:
    watch_url = f"https://www.youtube.com/watch?v={video_id}"
    try:
        async with httpx.AsyncClient(timeout=12.0) as client:
            response = await client.get(
                "https://www.youtube.com/oembed",
                params={
                    "url": watch_url,
                    "format": "json",
                },
            )
    except httpx.HTTPError:
        return None

    if response.status_code != 200:
        return None

    try:
        payload = response.json()
    except ValueError:
        return None

    title = str(payload.get("title", "") or "").strip()
    author = str(payload.get("author_name", "") or "").strip()
    thumbnail = str(payload.get("thumbnail_url", "") or "").strip()

    if not title:
        return None

    return {
        "title": title,
        "author": author,
        "thumbnail_url": thumbnail,
        "watch_url": watch_url,
    }




def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _normalize_phone_number(raw: str) -> tuple[str, bool, str, list[str]]:
    value = raw.strip()
    if not value:
        return "", False, "", []

    try:
        parsed = phonenumbers.parse(value, "US")
    except phonenumbers.NumberParseException:
        return "", False, "", []

    possible = phonenumbers.is_possible_number(parsed)
    valid = phonenumbers.is_valid_number(parsed)
    if not possible:
        return "", False, "", []

    e164 = phonenumbers.format_number(
        parsed,
        phonenumbers.PhoneNumberFormat.E164,
    )
    region = phone_geocoder.description_for_number(parsed, "en").strip()
    zones = list(phone_timezone.time_zones_for_number(parsed))
    return e164, valid, region, zones


def _twilio_lookup_credentials() -> tuple[str, str]:
    username = TWILIO_API_KEY or TWILIO_ACCOUNT_SID
    password = TWILIO_API_SECRET or TWILIO_AUTH_TOKEN
    return username, password


async def _lookup_caller_intelligence(raw_number: str) -> CallerIntelligenceResponse:
    e164, local_valid, region, zones = _normalize_phone_number(raw_number)
    if not e164:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Enter a valid phone number.",
        )

    username, password = _twilio_lookup_credentials()
    base = CallerIntelligenceResponse(
        query_number=raw_number.strip(),
        phone_number=e164,
        valid=local_valid,
        region=region,
        time_zones=zones,
        lookup_configured=bool(username and password),
    )

    if not username or not password:
        return base.model_copy(
            update={
                "lookup_error": (
                    "Caller-name/carrier lookup is not configured on the server yet."
                ),
            }
        )

    encoded_number = httpx.URL(
        "https://lookups.twilio.com"
    ).copy_with(
        path=f"/v2/PhoneNumbers/{e164}"
    )

    try:
        async with httpx.AsyncClient(
            timeout=15.0,
            auth=httpx.BasicAuth(username, password),
        ) as client:
            response = await client.get(
                encoded_number,
                params={
                    "Fields": "caller_name,line_type_intelligence",
                },
            )
    except httpx.HTTPError as exc:
        return base.model_copy(
            update={
                "provider": "twilio",
                "lookup_error": f"Lookup network error: {type(exc).__name__}",
            }
        )

    try:
        payload = response.json()
    except ValueError:
        payload = {}

    if response.status_code < 200 or response.status_code >= 300:
        detail = ""
        if isinstance(payload, dict):
            detail = str(
                payload.get("message")
                or payload.get("detail")
                or payload.get("code")
                or ""
            ).strip()
        return base.model_copy(
            update={
                "provider": "twilio",
                "lookup_error": detail or f"Twilio Lookup HTTP {response.status_code}",
            }
        )

    if not isinstance(payload, dict):
        return base.model_copy(
            update={
                "provider": "twilio",
                "lookup_error": "Twilio returned an invalid lookup payload.",
            }
        )

    caller = payload.get("caller_name")
    line = payload.get("line_type_intelligence")
    caller_map = caller if isinstance(caller, dict) else {}
    line_map = line if isinstance(line, dict) else {}

    return CallerIntelligenceResponse(
        query_number=raw_number.strip(),
        phone_number=str(payload.get("phone_number") or e164),
        national_format=str(payload.get("national_format") or ""),
        valid=bool(payload.get("valid", local_valid)),
        caller_name=str(caller_map.get("caller_name") or ""),
        caller_type=str(caller_map.get("caller_type") or ""),
        carrier_name=str(line_map.get("carrier_name") or ""),
        line_type=str(line_map.get("type") or ""),
        mobile_country_code=str(line_map.get("mobile_country_code") or ""),
        mobile_network_code=str(line_map.get("mobile_network_code") or ""),
        country_code=str(payload.get("country_code") or ""),
        region=region,
        time_zones=zones,
        provider="twilio",
        lookup_configured=True,
    )


def _sip_number(headers: list[dict[str, str]], name: str) -> str:
    wanted = name.strip().lower()
    for item in headers:
        if str(item.get("name", "")).strip().lower() != wanted:
            continue
        value = str(item.get("value", "") or "").strip()
        match = re.search(r"(?:sip:|tel:)(\+?[0-9]{7,20})", value, flags=re.IGNORECASE)
        if match:
            return match.group(1)
        return value[:100]
    return ""


async def _watch_bridge_phone_get(
    path: str,
    authorization: str | None,
) -> dict[str, object]:
    auth = (authorization or "").strip()
    if not auth or not WATCH_BRIDGE_PHONE_URL:
        raise RuntimeError("Watch Bridge phone transport is not configured.")

    async with httpx.AsyncClient(timeout=20.0) as client:
        response = await client.get(
            f"{WATCH_BRIDGE_PHONE_URL}{path}",
            headers={"Authorization": auth},
        )

    try:
        payload = response.json()
    except ValueError:
        payload = {}

    if response.status_code < 200 or response.status_code >= 300:
        detail = (
            str(payload.get("detail", "")).strip()
            if isinstance(payload, dict)
            else ""
        )
        raise RuntimeError(
            detail
            or f"Watch Bridge phone transport HTTP {response.status_code}."
        )

    return payload if isinstance(payload, dict) else {}


async def _phone_gateway_call(
    operation: str,
    **payload: object,
) -> dict[str, object]:
    if not CLIENT_TOKEN or not PHONE_GATEWAY_URL:
        raise RuntimeError("Phone message gateway is not configured.")

    async with httpx.AsyncClient(timeout=15.0) as client:
        response = await client.post(
            PHONE_GATEWAY_URL,
            headers={
                "Authorization": f"Bearer {CLIENT_TOKEN}",
                "Content-Type": "application/json",
            },
            json={"operation": operation, **payload},
        )

    try:
        data = response.json()
    except ValueError:
        data = {}

    if response.status_code < 200 or response.status_code >= 300:
        detail = str(data.get("error", "")).strip() if isinstance(data, dict) else ""
        raise RuntimeError(detail or f"Phone gateway HTTP {response.status_code}.")

    return data if isinstance(data, dict) else {}


async def _summarize_phone_call(
    caller_transcript: str,
    assistant_transcript: str,
) -> dict[str, object]:
    combined = (
        "CALLER:\n"
        + caller_transcript.strip()
        + "\n\nJARVIS:\n"
        + assistant_transcript.strip()
    ).strip()

    fallback = {
        "caller_name": "",
        "callback_number": "",
        "urgent": bool(
            re.search(
                r"\b(urgent|emergency|as soon as possible|asap|right away)\b",
                caller_transcript,
                flags=re.IGNORECASE,
            )
        ),
        "summary": caller_transcript.strip()[:1200]
        or "Caller ended before leaving a message.",
    }

    client: AsyncOpenAI | None = getattr(app.state, "frontier_openai", None)
    if client is None or not combined:
        return fallback

    try:
        response = await client.responses.create(
            model=FRONTIER_MODEL,
            instructions=(
                "Summarize a phone message for the owner of JARVIS. "
                "Return JSON only with keys caller_name, callback_number, urgent, summary. "
                "Do not invent a name or number. urgent must be true only when the caller "
                "indicates urgency, emergency, a deadline, or immediate attention."
            ),
            input=combined,
        )
        raw = (response.output_text or "").strip()
        parsed = json.loads(raw)
        if not isinstance(parsed, dict):
            return fallback
        return {
            "caller_name": str(parsed.get("caller_name", "") or "").strip()[:255],
            "callback_number": str(parsed.get("callback_number", "") or "").strip()[:100],
            "urgent": parsed.get("urgent") is True,
            "summary": str(parsed.get("summary", "") or "").strip()[:8000]
            or fallback["summary"],
        }
    except Exception:
        return fallback


async def _persist_phone_call(
    call_id: str,
    record: dict[str, object],
) -> None:
    caller_lines = record.get("caller_lines", [])
    assistant_lines = record.get("assistant_lines", [])
    caller_text = "\n".join(
        str(item).strip()
        for item in caller_lines
        if str(item).strip()
    )
    assistant_text = "\n".join(
        str(item).strip()
        for item in assistant_lines
        if str(item).strip()
    )
    summary = await _summarize_phone_call(caller_text, assistant_text)

    try:
        await _phone_gateway_call(
            "upsert_message",
            call_id=call_id,
            provider="openai_sip",
            from_number=str(record.get("from_number", "") or ""),
            to_number=str(record.get("to_number", "") or ""),
            caller_name=summary.get("caller_name", ""),
            callback_number=summary.get("callback_number", ""),
            urgent=summary.get("urgent") is True,
            summary=summary.get("summary", ""),
            transcript=caller_text,
            assistant_transcript=assistant_text,
            status=str(record.get("status", "completed") or "completed"),
            started_at=record.get("started_at"),
            completed_at=record.get("completed_at") or _utc_now(),
        )
    except Exception:
        pass


async def _monitor_realtime_phone_call(call_id: str) -> None:
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    record = ACTIVE_PHONE_CALLS.get(call_id)
    if not api_key or record is None:
        return

    url = "wss://api.openai.com/v1/realtime?call_id=" + call_id
    headers = {
        "Authorization": f"Bearer {api_key}",
        "OpenAI-Safety-Identifier": hashlib.sha256(
            f"jarvis-phone:{call_id}".encode("utf-8")
        ).hexdigest(),
    }

    try:
        async with websockets.connect(
            url,
            additional_headers=headers,
            open_timeout=15,
            close_timeout=10,
        ) as websocket:
            await websocket.send(
                json.dumps(
                    {
                        "type": "response.create",
                        "response": {
                            "instructions": (
                                "Greet the caller as JARVIS, Jerome's AI receptionist. "
                                "Say Jerome is unavailable right now. Ask for the caller's "
                                "name, best callback number, reason for calling, and whether "
                                "the matter is urgent. Listen naturally and confirm the "
                                "message back briefly before closing."
                            )
                        },
                    }
                )
            )

            async for raw in websocket:
                try:
                    event = json.loads(raw)
                except (TypeError, json.JSONDecodeError):
                    continue

                event_type = str(event.get("type", "") or "")

                if event_type == "conversation.item.input_audio_transcription.completed":
                    text = str(event.get("transcript", "") or "").strip()
                    if text:
                        lines = record.setdefault("caller_lines", [])
                        if isinstance(lines, list):
                            lines.append(text)

                elif event_type in {
                    "response.output_audio_transcript.done",
                    "response.output_text.done",
                }:
                    text = str(
                        event.get("transcript", "")
                        or event.get("text", "")
                        or ""
                    ).strip()
                    if text:
                        lines = record.setdefault("assistant_lines", [])
                        if isinstance(lines, list):
                            lines.append(text)

                elif event_type == "error":
                    error = event.get("error")
                    record["last_error"] = str(
                        error.get("message", "")
                        if isinstance(error, dict)
                        else "Realtime phone error"
                    )[:1000]

                elif event_type == "session.closed":
                    break
    except Exception as exc:
        record["last_error"] = f"{type(exc).__name__}: {exc}"[:1000]
    finally:
        record["status"] = "completed"
        record["completed_at"] = _utc_now()
        await _persist_phone_call(call_id, record)
        ACTIVE_PHONE_CALLS.pop(call_id, None)


async def _accept_openai_sip_call(
    call_id: str,
    from_number: str,
    to_number: str,
) -> None:
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is not configured.")

    instructions = (
        "You are JARVIS, Jerome's male AI cellular receptionist. "
        "Use a calm, masculine, cool, professional voice. "
        "Tell callers that you are JARVIS, an AI receptionist. "
        "Never pretend to be Jerome or a human employee. "
        "When Jerome is unavailable, collect the caller's name, callback number, "
        "reason for calling, important details, and whether it is urgent. "
        "Ask one question at a time, listen carefully, and confirm the message. "
        "Do not disclose private information about Jerome, his contacts, schedule, "
        "location, accounts, or prior conversations. "
        "Do not make commitments, payments, legal promises, or business agreements. "
        "If the caller asks for an emergency service, tell them to contact the "
        "appropriate emergency service directly."
    )

    session = {
        "type": "realtime",
        "model": REALTIME_MODEL,
        "instructions": instructions,
        "audio": {
            "input": {
                "transcription": {
                    "model": "gpt-4o-transcribe",
                    "language": "en",
                }
            },
            "output": {
                "voice": "cedar",
                "speed": 0.96,
            },
        },
    }

    async with httpx.AsyncClient(timeout=20.0) as client:
        response = await client.post(
            f"https://api.openai.com/v1/realtime/calls/{call_id}/accept",
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json=session,
        )

    if response.status_code < 200 or response.status_code >= 300:
        raise RuntimeError(
            f"OpenAI SIP accept failed with HTTP {response.status_code}."
        )

    ACTIVE_PHONE_CALLS[call_id] = {
        "call_id": call_id,
        "from_number": from_number,
        "to_number": to_number,
        "status": "active",
        "started_at": _utc_now(),
        "caller_lines": [],
        "assistant_lines": [],
    }

    task = asyncio.create_task(_monitor_realtime_phone_call(call_id))
    PHONE_CALL_TASKS.add(task)
    task.add_done_callback(PHONE_CALL_TASKS.discard)


@app.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    return HealthResponse(
        status="ok",
        service=APP_NAME,
        model=getattr(app.state, "ai_model", GATEWAY_MODEL),
        ai_configured=getattr(app.state, "openai", None) is not None,
        ai_provider=getattr(app.state, "ai_provider", "unconfigured"),
        chairman_auth_configured=bool(CHAIRMAN_TOKEN) or auth_ready(),
        google_chairman_auth_configured=auth_ready(),
        client_auth_configured=bool(CLIENT_TOKEN),
    )


@app.post("/v1/auth/google", response_model=AuthResponse)
async def google_auth(payload: GoogleAuthRequest) -> AuthResponse:
    identity = verify_google_chairman(payload.id_token.strip())
    access_token, expires_at = issue_session(identity)
    return AuthResponse(
        access_token=access_token,
        expires_at=expires_at,
        role="chairman",
        display_name=identity.display_name,
        email=identity.email,
        subscription_exempt=True,
    )


@app.get("/v1/auth/session", response_model=SessionResponse)
async def auth_session(
    authorization: Annotated[str | None, Header()] = None,
) -> SessionResponse:
    token = _extract_bearer(authorization)
    identity = verify_session(token)
    if identity is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="JARVIS session is invalid or expired.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return SessionResponse(
        authenticated=True,
        role=identity.role,
        display_name=identity.display_name,
        email=identity.email,
        subscription_exempt=identity.role == "chairman",
    )


@app.get("/v1/auth/check", response_model=AuthCheckResponse)
async def auth_check(
    authenticated_role: Annotated[str, Depends(authenticate_request)],
) -> AuthCheckResponse:
    return AuthCheckResponse(
        authenticated=True,
        role=authenticated_role,
    )




@app.websocket("/ws/jarvis")
async def jarvis_websocket(websocket: WebSocket) -> None:
    ticket = (websocket.query_params.get("ticket") or "").strip()
    role = _role_for_token(ticket)
    if role is None:
        await websocket.close(code=4401, reason="Unauthorized")
        return

    await websocket.accept()
    await websocket.send_json(
        {
            "type": "system",
            "message": "Jarvis online.",
            "role": role,
        }
    )

    try:
        while True:
            try:
                event = await asyncio.wait_for(
                    websocket.receive_json(),
                    timeout=25.0,
                )
            except asyncio.TimeoutError:
                await websocket.send_json(
                    {
                        "type": "ping",
                        "ping_id": str(time.time_ns()),
                    }
                )
                continue

            if not isinstance(event, dict):
                continue

            event_type = str(event.get("type", "") or "")
            if event_type in {"pong", "tool_result"}:
                continue

            if event_type == "cancel_response":
                await websocket.send_json(
                    {
                        "type": "response_cancelled",
                        "request_id": event.get("request_id"),
                    }
                )
                continue

            if event_type == "user_text":
                request_id = str(event.get("request_id", "") or "")
                payload = event.get("payload")
                prompt = (
                    str(payload.get("text", "") or "").strip()
                    if isinstance(payload, dict)
                    else ""
                )
                client: AsyncOpenAI | None = getattr(
                    app.state,
                    "frontier_openai",
                    None,
                )
                if not request_id or not prompt or client is None:
                    await websocket.send_json(
                        {
                            "type": "error",
                            "request_id": request_id or None,
                            "code": "invalid_request",
                            "message": "Jarvis could not process that WebSocket request.",
                            "retryable": True,
                        }
                    )
                    continue

                try:
                    response = await client.responses.create(
                        model=FRONTIER_MODEL,
                        instructions=(
                            "You are JARVIS, a precise personal AI assistant. "
                            f"Authenticated application role: {role}."
                        ),
                        input=prompt,
                        reasoning={"effort": "high"},
                    )
                    answer = (response.output_text or "").strip()
                    if not answer:
                        raise RuntimeError("Empty response")
                    await websocket.send_json(
                        {
                            "type": "agent_text_chunk",
                            "request_id": request_id,
                            "chunk_index": 0,
                            "payload": {
                                "chunk_index": 0,
                                "text_chunk": answer,
                                "is_final": True,
                            },
                        }
                    )
                except Exception as exc:
                    await websocket.send_json(
                        {
                            "type": "error",
                            "request_id": request_id,
                            "code": "jarvis_ws_request_failed",
                            "message": f"Jarvis request failed: {type(exc).__name__}",
                            "retryable": True,
                        }
                    )
    except WebSocketDisconnect:
        return


@app.post("/memory")
async def save_memory(
    payload: MemorySaveRequest,
    authorization: Annotated[str | None, Header()] = None,
    authenticated_role: Annotated[str, Depends(authenticate_request)] = "client",
) -> dict[str, object]:
    del authenticated_role
    try:
        return await _memory_gateway_call(
            "save_memory",
            authorization,
            text=payload.text,
            kind=payload.kind,
            importance=payload.importance,
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Memory storage unavailable: {type(exc).__name__}",
        ) from exc


@app.get("/memory/context")
async def memory_context(
    q: str = "",
    authorization: Annotated[str | None, Header()] = None,
    authenticated_role: Annotated[str, Depends(authenticate_request)] = "client",
) -> dict[str, object]:
    del authenticated_role
    try:
        return await _memory_gateway_call(
            "query_memory",
            authorization,
            query=q[:1000],
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Memory lookup unavailable: {type(exc).__name__}",
        ) from exc


@app.get("/people")
async def list_people(
    authorization: Annotated[str | None, Header()] = None,
    authenticated_role: Annotated[str, Depends(authenticate_request)] = "client",
) -> dict[str, object]:
    del authenticated_role
    try:
        return await _memory_gateway_call("list_people", authorization)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"People Memory unavailable: {type(exc).__name__}",
        ) from exc


@app.post("/people")
async def create_person(
    payload: PersonCreateRequest,
    authorization: Annotated[str | None, Header()] = None,
    authenticated_role: Annotated[str, Depends(authenticate_request)] = "client",
) -> dict[str, object]:
    del authenticated_role
    try:
        return await _memory_gateway_call(
            "create_person",
            authorization,
            display_name=payload.display_name,
            relationship=payload.relationship,
            notes=payload.notes,
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"People Memory unavailable: {type(exc).__name__}",
        ) from exc


@app.get("/people/presence/current")
async def current_person_presence(
    authorization: Annotated[str | None, Header()] = None,
    authenticated_role: Annotated[str, Depends(authenticate_request)] = "client",
) -> dict[str, object]:
    del authenticated_role
    try:
        return await _memory_gateway_call("current_presence", authorization)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"People presence unavailable: {type(exc).__name__}",
        ) from exc


@app.delete("/people/presence/current")
async def clear_person_presence(
    authorization: Annotated[str | None, Header()] = None,
    authenticated_role: Annotated[str, Depends(authenticate_request)] = "client",
) -> dict[str, object]:
    del authenticated_role
    try:
        return await _memory_gateway_call("clear_presence", authorization)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"People presence unavailable: {type(exc).__name__}",
        ) from exc


@app.post("/people/{person_id}/present")
async def confirm_person_present(
    person_id: str,
    authorization: Annotated[str | None, Header()] = None,
    authenticated_role: Annotated[str, Depends(authenticate_request)] = "client",
) -> dict[str, object]:
    del authenticated_role
    try:
        return await _memory_gateway_call(
            "confirm_present",
            authorization,
            person_id=person_id[:100],
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"People presence unavailable: {type(exc).__name__}",
        ) from exc


@app.delete("/people/{person_id}")
async def delete_person(
    person_id: str,
    authorization: Annotated[str | None, Header()] = None,
    authenticated_role: Annotated[str, Depends(authenticate_request)] = "client",
) -> dict[str, object]:
    del authenticated_role
    try:
        return await _memory_gateway_call(
            "delete_person",
            authorization,
            person_id=person_id[:100],
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"People Memory unavailable: {type(exc).__name__}",
        ) from exc


@app.post("/vision/frame")
async def upload_vision_frame(
    frame: UploadFile = File(...),
    authorization: Annotated[str | None, Header()] = None,
    authenticated_role: Annotated[str, Depends(authenticate_request)] = "client",
) -> dict[str, object]:
    del authenticated_role
    key = _vision_key(authorization)
    if not key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid client authentication.",
        )

    data = await frame.read(VISION_FRAME_MAX_BYTES + 1)
    if not data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Vision frame is empty.",
        )
    if len(data) > VISION_FRAME_MAX_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Vision frames must be 8 MB or smaller.",
        )

    mime = _detect_image_mime(data, frame.content_type)
    if mime is None:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Vision frame must be JPEG, PNG, or WebP.",
        )

    LATEST_VISION_FRAMES[key] = {
        "data": data,
        "mime": mime,
        "captured_at": time.monotonic(),
    }

    return {
        "status": "accepted",
        "bytes": len(data),
        "expires_in_seconds": int(VISION_FRAME_TTL_SECONDS),
    }


@app.delete("/vision/frame")
async def clear_vision_frame(
    authorization: Annotated[str | None, Header()] = None,
    authenticated_role: Annotated[str, Depends(authenticate_request)] = "client",
) -> dict[str, object]:
    del authenticated_role
    key = _vision_key(authorization)
    if key:
        LATEST_VISION_FRAMES.pop(key, None)
    return {"status": "cleared"}


@app.get(
    "/v1/phone/caller-intelligence",
    response_model=CallerIntelligenceResponse,
)
async def phone_caller_intelligence(
    number: str,
    authenticated_role: Annotated[str, Depends(authenticate_request)],
) -> CallerIntelligenceResponse:
    del authenticated_role
    return await _lookup_caller_intelligence(number)


@app.get("/v1/phone/status", response_model=PhoneReceptionistStatus)
async def phone_receptionist_status(
    authorization: Annotated[str | None, Header()] = None,
    authenticated_role: Annotated[str, Depends(authenticate_request)] = "client",
) -> PhoneReceptionistStatus:
    del authenticated_role

    try:
        payload = await _watch_bridge_phone_get(
            "/main/phone/status",
            authorization,
        )
        return PhoneReceptionistStatus(
            configured=bool(payload.get("active", False)),
            provider=str(payload.get("provider", "vapi") or "vapi"),
            phone_number=str(
                payload.get("phoneNumber", "+15318679252") or "+15318679252"
            ),
            active_calls=0,
        )
    except Exception:
        return PhoneReceptionistStatus(
            configured=bool(
                os.getenv("OPENAI_API_KEY", "").strip()
                and PHONE_WEBHOOK_SECRET
            ),
            provider="openai_sip",
            phone_number=RECEPTIONIST_NUMBER,
            active_calls=len(ACTIVE_PHONE_CALLS),
        )


@app.get("/v1/phone/messages")
async def phone_receptionist_messages(
    authorization: Annotated[str | None, Header()] = None,
    authenticated_role: Annotated[str, Depends(authenticate_request)] = "client",
) -> dict[str, object]:
    del authenticated_role

    try:
        payload = await _watch_bridge_phone_get(
            "/main/phone/messages",
            authorization,
        )
        raw_messages = payload.get("messages", [])
        messages: list[dict[str, object]] = []

        if isinstance(raw_messages, list):
            for item in raw_messages:
                if not isinstance(item, dict):
                    continue
                messages.append(
                    {
                        "call_id": str(item.get("id", "") or ""),
                        "from_number": str(item.get("callerPhone", "") or ""),
                        "to_number": str(payload.get("phoneNumber", "") or ""),
                        "caller_name": str(item.get("callerName", "") or ""),
                        "callback_number": str(
                            item.get("callbackNumber", "") or ""
                        ),
                        "urgent": bool(item.get("urgent", False)),
                        "summary": str(item.get("summary", "") or ""),
                        "transcript": str(item.get("transcript", "") or ""),
                        "assistant_transcript": "",
                        "status": str(item.get("status", "completed") or "completed"),
                        "started_at": item.get("createdAt"),
                        "completed_at": item.get("endedAt"),
                    }
                )

        return {"messages": messages}
    except Exception:
        try:
            payload = await _phone_gateway_call("list_messages", limit=100)
            messages = payload.get("messages", [])
            return {"messages": messages if isinstance(messages, list) else []}
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Phone message storage unavailable: {type(exc).__name__}",
            ) from exc


@app.post("/v1/phone/openai-webhook", include_in_schema=False)
async def openai_phone_webhook(request: Request) -> dict[str, bool]:
    if not PHONE_WEBHOOK_SECRET:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="OPENAI_WEBHOOK_SECRET is not configured.",
        )

    raw = await request.body()
    try:
        verifier = OpenAI(
            api_key=os.getenv("OPENAI_API_KEY", "").strip() or "webhook-verification-only",
            webhook_secret=PHONE_WEBHOOK_SECRET,
        )
        event = verifier.webhooks.unwrap(
            raw,
            dict(request.headers),
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid OpenAI phone webhook signature.",
        ) from exc

    event_type = str(getattr(event, "type", "") or "")
    if event_type != "realtime.call.incoming":
        return {"ok": True}

    data = getattr(event, "data", None)
    call_id = str(getattr(data, "call_id", "") or "").strip()
    raw_headers = getattr(data, "sip_headers", None) or []

    sip_headers: list[dict[str, str]] = []
    for item in raw_headers:
        if isinstance(item, dict):
            sip_headers.append(
                {
                    "name": str(item.get("name", "") or ""),
                    "value": str(item.get("value", "") or ""),
                }
            )
        else:
            sip_headers.append(
                {
                    "name": str(getattr(item, "name", "") or ""),
                    "value": str(getattr(item, "value", "") or ""),
                }
            )

    if not call_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Incoming phone webhook contained no call_id.",
        )

    from_number = _sip_number(sip_headers, "From")
    to_number = _sip_number(sip_headers, "To")
    await _accept_openai_sip_call(
        call_id,
        from_number,
        to_number,
    )
    return {"ok": True}


@app.post("/v1/music/search", response_model=MusicSearchResponse)
async def music_search(
    payload: MusicSearchRequest,
    authenticated_role: Annotated[str, Depends(authenticate_request)],
) -> MusicSearchResponse:
    client: AsyncOpenAI | None = getattr(app.state, "frontier_openai", None)
    if client is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Internet music lookup requires OPENAI_API_KEY on the server.",
        )

    query = payload.query.strip()
    search_prompt = (
        "Search the public web for the exact song requested below. "
        "Prefer the official artist channel, the artist's Topic channel, "
        "the official music video, or another clearly authorized YouTube upload. "
        "Return several direct YouTube watch URLs if possible. Do not invent URLs. "
        "Do not return lyric reuploads, reaction videos, covers, remixes, or unofficial "
        "copies unless the user's request specifically asks for one.\n\n"
        f"Song request: {query}"
    )

    try:
        response = await client.responses.create(
            model=FRONTIER_MODEL,
            instructions=(
                "You are JARVIS Music Resolver. Find verified, legal embedded playback "
                "sources. Prefer official or authorized YouTube uploads. Never fabricate "
                "a video ID or URL."
            ),
            input=search_prompt,
            tools=[{"type": "web_search"}],
            reasoning={"effort": "medium"},
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Internet music search failed: {type(exc).__name__}",
        ) from exc

    candidate_urls: list[str] = []
    seen_urls: set[str] = set()

    for source in _extract_web_sources(response):
        url = source.get("url", "").strip()
        if url and url not in seen_urls:
            seen_urls.add(url)
            candidate_urls.append(url)

    output_text = (response.output_text or "").strip()
    for match in re.findall(
        r"https?://(?:www\.)?(?:music\.)?(?:youtube\.com/watch\?[^\s<>)\]]+|youtu\.be/[A-Za-z0-9_-]{11})",
        output_text,
    ):
        url = match.rstrip(".,;:'\"")
        if url not in seen_urls:
            seen_urls.add(url)
            candidate_urls.append(url)

    validated: list[tuple[str, dict[str, str]]] = []
    for url in candidate_urls[:12]:
        video_id = _youtube_video_id(url)
        if not video_id:
            continue
        metadata = await _validate_youtube_video(video_id)
        if metadata is None:
            continue
        validated.append((video_id, metadata))
        if len(validated) >= 5:
            break

    if not validated:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Jarvis could not find a verified playable YouTube result for that song.",
        )

    video_id, metadata = validated[0]

    return MusicSearchResponse(
        query=query,
        provider="youtube",
        video_id=video_id,
        title=metadata["title"],
        author=metadata["author"],
        thumbnail_url=metadata["thumbnail_url"],
        watch_url=metadata["watch_url"],
    )


@app.post("/v1/realtime/client-secret")
async def realtime_client_secret(
    payload: RealtimeClientSecretRequest,
    authenticated_role: Annotated[str, Depends(authenticate_request)],
) -> dict[str, object]:
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Realtime voice requires OPENAI_API_KEY on the server.",
        )

    safety_identifier = hashlib.sha256(
        f"jarvis:{authenticated_role}:primary".encode("utf-8")
    ).hexdigest()

    requested_voice = payload.voice.strip().lower()
    voice = (
        requested_voice
        if requested_voice in REALTIME_ALLOWED_VOICES
        else REALTIME_VOICE
    )
    mood = payload.mood.strip().lower()
    mood_instruction = REALTIME_MOOD_INSTRUCTIONS.get(
        mood,
        REALTIME_MOOD_INSTRUCTIONS["confident"],
    )
    continuity = payload.context.strip()

    session_config = {
        "session": {
            "type": "realtime",
            "model": REALTIME_MODEL,
            "instructions": (
                "You are JARVIS, a male personal AI assistant with a cool, capable "
                "presence. Speak naturally and stay concise unless detail is useful. "
                + mood_instruction
                + " Adapt emotion to the conversation while staying authentic and "
                "controlled. Remember that device/tool actions must be verified, and "
                "never claim an external action succeeded without confirmation."
                + (
                    " Recent continuity from the prior voice session: " + continuity
                    if continuity
                    else ""
                )
            ),
            "audio": {
                "input": {
                    "transcription": {
                        "model": "gpt-live-transcribe",
                        "delay": "low",
                    },
                },
                "output": {
                    "voice": voice,
                },
            },
            "tool_choice": "auto",
            "tools": [
                {
                    "type": "function",
                    "name": "play_music",
                    "description": (
                        "Search the internet for the requested song and play the "
                        "verified result inside JARVIS."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "Song, artist, album, or track request.",
                            },
                        },
                        "required": ["query"],
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "pause_music",
                    "description": "Pause music currently playing inside JARVIS.",
                    "parameters": {
                        "type": "object",
                        "properties": {},
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "resume_music",
                    "description": "Resume the current JARVIS music track.",
                    "parameters": {
                        "type": "object",
                        "properties": {},
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "list_cloud_devices",
                    "description": (
                        "List JARVIS devices registered on the user's secure cloud "
                        "device network and report which are online."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {},
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "handoff_jarvis_device",
                    "description": (
                        "Move JARVIS presence to another online JARVIS device by "
                        "device name."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "target_device_name": {
                                "type": "string",
                                "description": "Name of the destination device.",
                            },
                        },
                        "required": ["target_device_name"],
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "send_cloud_device_command",
                    "description": (
                        "Send an approved command to another online JARVIS device. "
                        "Supported actions include speak_text, play_music, music_pause, "
                        "music_resume, vision_refresh, flashlight_on, flashlight_off, "
                        "system_action, device_diagnose, device_scan_security, "
                        "device_repair, ping, and avatar_handoff."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "target_device_name": {
                                "type": "string",
                                "description": "Name of the target JARVIS device.",
                            },
                            "action": {
                                "type": "string",
                                "description": "Allowed cloud-device action.",
                            },
                            "parameters": {
                                "type": "object",
                                "description": "Parameters for the target action.",
                            },
                        },
                        "required": ["target_device_name", "action"],
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "phone_active_call",
                    "description": "Report the current Android cellular call state.",
                    "parameters": {
                        "type": "object",
                        "properties": {},
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "phone_answer_call",
                    "description": "Answer the currently ringing cellular call.",
                    "parameters": {
                        "type": "object",
                        "properties": {},
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "phone_reject_call",
                    "description": "Reject the currently ringing cellular call.",
                    "parameters": {
                        "type": "object",
                        "properties": {},
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "phone_end_call",
                    "description": "End the current cellular call.",
                    "parameters": {
                        "type": "object",
                        "properties": {},
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "phone_set_mute",
                    "description": "Mute or unmute the current cellular call.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "muted": {"type": "boolean"},
                        },
                        "required": ["muted"],
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "phone_set_speaker",
                    "description": "Turn speakerphone on or off for the current cellular call.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "enabled": {"type": "boolean"},
                        },
                        "required": ["enabled"],
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "device_diagnose",
                    "description": (
                        "Diagnose this Android device for storage, memory, network, "
                        "Bluetooth, battery, and other supported system problems."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {},
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "device_scan_security",
                    "description": (
                        "Scan visible installed apps for concrete malware and security "
                        "risk indicators. Findings are heuristic unless a signature or "
                        "reputation engine independently confirms a threat."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {},
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "device_repair_issue",
                    "description": (
                        "Repair a diagnosed Android issue when permitted, or open the "
                        "exact Android repair controls when user confirmation is required."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "target": {
                                "type": "string",
                                "enum": [
                                    "storage",
                                    "memory",
                                    "internet",
                                    "bluetooth",
                                    "battery",
                                    "apps",
                                    "security",
                                    "system_update",
                                    "date_time",
                                    "display",
                                    "sound",
                                    "accessibility",
                                    "jarvis_cache",
                                ],
                            },
                        },
                        "required": ["target"],
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "system_global_action",
                    "description": "Perform an Android Back, Home, Recents, Notifications, or Quick Settings action.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "action": {
                                "type": "string",
                                "enum": ["back", "home", "recents", "notifications", "quick_settings"],
                            },
                        },
                        "required": ["action"],
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "system_type_text",
                    "description": "Type user-approved text into the currently focused Android text field.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "text": {"type": "string"},
                        },
                        "required": ["text"],
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "system_launch_app",
                    "description": "Launch an installed Android app by exact package name.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "package_name": {"type": "string"},
                        },
                        "required": ["package_name"],
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "system_tap",
                    "description": "Tap a screen coordinate after user approval.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "x": {"type": "number"},
                            "y": {"type": "number"},
                        },
                        "required": ["x", "y"],
                        "additionalProperties": False,
                    },
                },
                {
                    "type": "function",
                    "name": "system_swipe",
                    "description": "Swipe between screen coordinates after user approval.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "start_x": {"type": "number"},
                            "start_y": {"type": "number"},
                            "end_x": {"type": "number"},
                            "end_y": {"type": "number"},
                            "duration_ms": {"type": "integer"},
                        },
                        "required": ["start_x", "start_y", "end_x", "end_y"],
                        "additionalProperties": False,
                    },
                },
            ],
        }
    }

    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.post(
                "https://api.openai.com/v1/realtime/client_secrets",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                    "OpenAI-Safety-Identifier": safety_identifier,
                },
                json=session_config,
            )
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Realtime credential request failed: {type(exc).__name__}",
        ) from exc

    if response.status_code < 200 or response.status_code >= 300:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="OpenAI Realtime credential service rejected the request.",
        )

    payload = response.json()
    if not isinstance(payload, dict) or not str(payload.get("value", "")).strip():
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="OpenAI Realtime returned no usable client secret.",
        )

    return payload


@app.post("/v1/frontier/query", response_model=FrontierQueryResponse)
async def frontier_query(
    payload: FrontierQueryRequest,
    authorization: Annotated[str | None, Header()] = None,
    authenticated_role: Annotated[str, Depends(authenticate_request)] = "client",
) -> FrontierQueryResponse:
    client: AsyncOpenAI | None = getattr(app.state, "frontier_openai", None)
    if client is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Frontier AI requires OPENAI_API_KEY on the server.",
        )

    mode = payload.mode.strip().lower()
    if mode not in {"reason", "research", "code"}:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Unsupported frontier mode.",
        )

    tools: list[dict[str, object]] = []
    reasoning_effort = "high"

    if mode == "research":
        tools = [{"type": "web_search"}]
        reasoning_effort = "xhigh"
    elif mode == "code":
        tools = [
            {
                "type": "code_interpreter",
                "container": {"type": "auto"},
            }
        ]
        reasoning_effort = "high"

    instructions = (
        "You are JARVIS Frontier Core. Work as one unified assistant. "
        "Be precise, verify results, state limitations, and do not claim a tool "
        "succeeded unless its result confirms success. "
        f"Authenticated application role: {authenticated_role}."
    )

    input_payload: object = payload.prompt.strip()
    image_url: str | None = None

    if payload.image_base64:
        image_url = "data:image/png;base64," + payload.image_base64.strip()
    elif _prompt_requests_camera_context(payload.prompt):
        image_url = _latest_vision_data_url(authorization)

    if image_url:
        input_payload = [
            {
                "role": "user",
                "content": [
                    {
                        "type": "input_text",
                        "text": payload.prompt.strip(),
                    },
                    {
                        "type": "input_image",
                        "image_url": image_url,
                    },
                ],
            }
        ]

    request_kwargs: dict[str, object] = {
        "model": FRONTIER_MODEL,
        "instructions": instructions,
        "input": input_payload,
        "reasoning": {"effort": reasoning_effort},
    }
    if tools:
        request_kwargs["tools"] = tools

    try:
        response = await client.responses.create(**request_kwargs)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Frontier AI request failed: {type(exc).__name__}",
        ) from exc

    answer = (response.output_text or "").strip()
    if not answer:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Frontier AI returned no usable text output.",
        )

    return FrontierQueryResponse(
        answer=answer,
        model=FRONTIER_MODEL,
        mode=mode,
        sources=_extract_web_sources(response) if mode == "research" else [],
    )


@app.post("/v1/frontier/file", response_model=FrontierQueryResponse)
async def frontier_file(
    document: UploadFile = File(...),
    prompt: str = Form(default="Analyze this file and summarize the important information."),
    authenticated_role: Annotated[str, Depends(authenticate_request)] = "client",
) -> FrontierQueryResponse:
    client: AsyncOpenAI | None = getattr(app.state, "frontier_openai", None)
    if client is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Document intelligence requires OPENAI_API_KEY on the server.",
        )

    filename = (document.filename or "document").strip()[:255] or "document"
    data = await document.read()
    if not data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="The selected file is empty.",
        )
    if len(data) > 50 * 1024 * 1024:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Files must be 50 MB or smaller.",
        )

    uploaded = None
    try:
        uploaded = await client.files.create(
            file=(
                filename,
                data,
                document.content_type or "application/octet-stream",
            ),
            purpose="user_data",
        )

        response = await client.responses.create(
            model=FRONTIER_MODEL,
            instructions=(
                "You are JARVIS Document Intelligence. Analyze the supplied file "
                "carefully. Distinguish what is in the file from your own analysis. "
                "Do not invent missing text, tables, signatures, dates, or figures. "
                f"Authenticated application role: {authenticated_role}."
            ),
            input=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "input_file",
                            "file_id": uploaded.id,
                        },
                        {
                            "type": "input_text",
                            "text": prompt.strip()
                            or "Analyze this file and summarize the important information.",
                        },
                    ],
                }
            ],
            reasoning={"effort": "high"},
        )

        answer = (response.output_text or "").strip()
        if not answer:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Document intelligence returned no usable output.",
            )

        return FrontierQueryResponse(
            answer=answer,
            model=FRONTIER_MODEL,
            mode="file",
            sources=[],
        )
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Document intelligence failed: {type(exc).__name__}",
        ) from exc
    finally:
        if uploaded is not None:
            try:
                await client.files.delete(uploaded.id)
            except Exception:
                pass


@app.post("/v1/frontier/image", response_model=FrontierImageResponse)
async def frontier_image(
    payload: FrontierImageRequest,
    authenticated_role: Annotated[str, Depends(authenticate_request)],
) -> FrontierImageResponse:
    del authenticated_role

    client: AsyncOpenAI | None = getattr(app.state, "frontier_openai", None)
    if client is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Image generation requires OPENAI_API_KEY on the server.",
        )

    try:
        image_result = await client.images.generate(
            model=IMAGE_MODEL,
            prompt=payload.prompt.strip(),
            size="1024x1024",
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Image generation failed: {type(exc).__name__}",
        ) from exc

    data = getattr(image_result, "data", None) or []
    image_base64 = str(getattr(data[0], "b64_json", "") or "") if data else ""
    if not image_base64:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Image generation returned no image data.",
        )

    return FrontierImageResponse(
        image_base64=image_base64,
        model=IMAGE_MODEL,
    )


@app.post("/_api/v1/legal/query", response_model=LegalQueryResponse, include_in_schema=False)
@app.post("/v1/legal/query", response_model=LegalQueryResponse)
async def legal_query(
    payload: LegalQueryRequest,
    authenticated_role: Annotated[str, Depends(authenticate_request)],
) -> LegalQueryResponse:
    requested_role = payload.role.strip().lower()
    if requested_role == "chairman" and authenticated_role != "chairman":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Chairman authority requires Chairman authentication.",
        )

    effective_role = "chairman" if authenticated_role == "chairman" else "client"

    client: AsyncOpenAI | None = getattr(app.state, "openai", None)
    if client is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="AI provider credential is not configured on the server.",
        )

    model = getattr(app.state, "ai_model", GATEWAY_MODEL)
    instructions = f"{LEGAL_INSTRUCTIONS}\n\n{_role_context(effective_role)}"

    try:
        response = await client.responses.create(
            model=model,
            instructions=instructions,
            input=payload.prompt.strip(),
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"AI provider request failed: {type(exc).__name__}",
        ) from exc

    answer = (response.output_text or "").strip()
    if not answer:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="AI provider returned no usable text output.",
        )

    return LegalQueryResponse(
        answer=answer,
        model=model,
        matter_id=payload.matter_id,
    )
