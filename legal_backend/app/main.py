from __future__ import annotations

import hashlib
import hmac
import os
from contextlib import asynccontextmanager
from typing import Annotated

import httpx
from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile, status
from openai import AsyncOpenAI
from pydantic import BaseModel, Field

from .auth_google import auth_ready, issue_session, verify_google_chairman, verify_session

APP_NAME = "JARVIS Legal Enterprise API"
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-5.6-sol").strip() or "gpt-5.6-sol"
FRONTIER_MODEL = os.getenv("JARVIS_FRONTIER_MODEL", "gpt-5.6-sol").strip() or "gpt-5.6-sol"
IMAGE_MODEL = os.getenv("JARVIS_IMAGE_MODEL", "gpt-image-2.5-sunburst").strip() or "gpt-image-2.5-sunburst"
REALTIME_MODEL = os.getenv("JARVIS_REALTIME_MODEL", "gpt-realtime-2.1").strip() or "gpt-realtime-2.1"
REALTIME_VOICE = os.getenv("JARVIS_REALTIME_VOICE", "marin").strip() or "marin"
GATEWAY_MODEL = os.getenv("AI_GATEWAY_MODEL", f"openai/{OPENAI_MODEL}").strip() or f"openai/{OPENAI_MODEL}"
GROQ_MODEL = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile").strip() or "llama-3.3-70b-versatile"
CHAIRMAN_TOKEN = os.getenv("JARVIS_CHAIRMAN_TOKEN", "").strip()
CLIENT_TOKEN = os.getenv("JARVIS_CLIENT_TOKEN", "").strip()
WATCH_PHONE_BASE = (
    os.getenv(
        "JARVIS_WATCH_PHONE_BASE",
        "https://jarvis-watch-bridge-api.onrender.com",
    ).strip().rstrip("/")
)
PHONE_BRIDGE_TOKEN = os.getenv("JARVIS_PHONE_BRIDGE_TOKEN", "").strip()

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


async def authenticate_request(
    authorization: Annotated[str | None, Header()] = None,
) -> str:
    supplied = _extract_bearer(authorization)
    if not supplied:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid client authentication.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    session_identity = verify_session(supplied)
    if session_identity is not None and session_identity.role == "chairman":
        return "chairman"

    # Transitional compatibility only. New Chairman builds use Google OIDC +
    # server-issued sessions; this static token can be removed after migration.
    if CHAIRMAN_TOKEN and hmac.compare_digest(supplied, CHAIRMAN_TOKEN):
        return "chairman"
    if CLIENT_TOKEN and hmac.compare_digest(supplied, CLIENT_TOKEN):
        return "client"

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid client authentication.",
        headers={"WWW-Authenticate": "Bearer"},
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


async def _watch_phone_bridge_get(path: str) -> dict[str, object]:
    if not PHONE_BRIDGE_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Shared JARVIS phone bridge is not configured.",
        )

    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.get(
                f"{WATCH_PHONE_BASE}{path}",
                headers={
                    "Authorization": f"Bearer {PHONE_BRIDGE_TOKEN}",
                    "Accept": "application/json",
                },
            )
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Shared JARVIS phone bridge is unavailable: {type(exc).__name__}",
        ) from exc

    if response.status_code < 200 or response.status_code >= 300:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Shared JARVIS phone bridge rejected the request.",
        )

    payload = response.json()
    if not isinstance(payload, dict):
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Shared JARVIS phone bridge returned an invalid response.",
        )

    return payload


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


@app.get("/v1/phone/status")
async def shared_phone_status(
    authenticated_role: Annotated[str, Depends(authenticate_request)],
) -> dict[str, object]:
    del authenticated_role
    return await _watch_phone_bridge_get("/phone/bridge/status")


@app.get("/v1/phone/messages")
async def shared_phone_messages(
    authenticated_role: Annotated[str, Depends(authenticate_request)],
) -> dict[str, object]:
    del authenticated_role
    return await _watch_phone_bridge_get("/phone/bridge/messages")


@app.post("/v1/realtime/client-secret")
async def realtime_client_secret(
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

    session_config = {
        "session": {
            "type": "realtime",
            "model": REALTIME_MODEL,
            "instructions": (
                "You are JARVIS, a concise, capable personal AI assistant. "
                "Speak naturally, remember that device/tool actions must be verified, "
                "and never claim an external action succeeded without confirmation."
            ),
            "audio": {
                "output": {
                    "voice": REALTIME_VOICE,
                },
            },
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
    authenticated_role: Annotated[str, Depends(authenticate_request)],
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
    if payload.image_base64:
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
                        "image_url": (
                            "data:image/png;base64,"
                            + payload.image_base64.strip()
                        ),
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
