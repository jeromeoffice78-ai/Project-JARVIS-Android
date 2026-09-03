from __future__ import annotations

import hmac
import os
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import Depends, FastAPI, Header, HTTPException, status
from openai import AsyncOpenAI
from pydantic import BaseModel, Field

APP_NAME = "JARVIS Legal Enterprise API"
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-5.6-sol").strip() or "gpt-5.6-sol"
GATEWAY_MODEL = os.getenv("AI_GATEWAY_MODEL", f"openai/{OPENAI_MODEL}").strip() or f"openai/{OPENAI_MODEL}"
CHAIRMAN_TOKEN = os.getenv("JARVIS_CHAIRMAN_TOKEN", "").strip()
CLIENT_TOKEN = os.getenv("JARVIS_CLIENT_TOKEN", "").strip()

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
    client_auth_configured: bool


def _build_ai_client() -> tuple[AsyncOpenAI | None, str, str]:
    """Prefer Vercel AI Gateway OIDC, then Gateway API key, then direct OpenAI.

    Vercel injects VERCEL_OIDC_TOKEN into deployed Functions. AI Gateway accepts that
    token as bearer auth, allowing production AI without placing a provider key in
    the Android app or repository.
    """

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
    app.state.openai = client
    app.state.ai_provider = provider
    app.state.ai_model = model
    yield
    if client is not None:
        await client.close()


app = FastAPI(title=APP_NAME, version="1.2.0", lifespan=lifespan)


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
    if not CHAIRMAN_TOKEN and not CLIENT_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Server authentication is not configured.",
        )

    supplied = _extract_bearer(authorization)
    if not supplied:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid client authentication.",
            headers={"WWW-Authenticate": "Bearer"},
        )

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


@app.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    return HealthResponse(
        status="ok",
        service=APP_NAME,
        model=getattr(app.state, "ai_model", GATEWAY_MODEL),
        ai_configured=getattr(app.state, "openai", None) is not None,
        ai_provider=getattr(app.state, "ai_provider", "unconfigured"),
        chairman_auth_configured=bool(CHAIRMAN_TOKEN),
        client_auth_configured=bool(CLIENT_TOKEN),
    )


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
    except Exception as exc:  # The API boundary converts provider failures to 502.
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
