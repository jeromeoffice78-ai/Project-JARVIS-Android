from __future__ import annotations

import hmac
import os
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import Depends, FastAPI, Header, HTTPException, status
from openai import AsyncOpenAI
from pydantic import BaseModel, Field

APP_NAME = "JARVIS Legal Enterprise API"
DEFAULT_MODEL = os.getenv("OPENAI_MODEL", "gpt-5.6-sol").strip() or "gpt-5.6-sol"
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


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.openai = AsyncOpenAI(api_key=os.environ.get("OPENAI_API_KEY"))
    yield
    await app.state.openai.close()


app = FastAPI(title=APP_NAME, version="1.0.0", lifespan=lifespan)


def _extract_bearer(value: str | None) -> str:
    if not value:
        return ""
    prefix = "Bearer "
    if not value.startswith(prefix):
        return ""
    return value[len(prefix) :].strip()


async def require_client_token(
    authorization: Annotated[str | None, Header()] = None,
) -> None:
    if not CLIENT_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Server client authentication is not configured.",
        )

    supplied = _extract_bearer(authorization)
    if not supplied or not hmac.compare_digest(supplied, CLIENT_TOKEN):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid client authentication.",
            headers={"WWW-Authenticate": "Bearer"},
        )


def _role_context(role: str) -> str:
    normalized = role.strip().lower()
    if normalized == "chairman":
        return (
            "Authenticated application role: CHAIRMAN. Jerome Office is the founder, "
            "Chairman, 100% owner, final enterprise authority, and subscription-exempt owner."
        )
    return f"Authenticated application role: {normalized or 'client'}."


@app.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    return HealthResponse(status="ok", service=APP_NAME, model=DEFAULT_MODEL)


@app.post(
    "/v1/legal/query",
    response_model=LegalQueryResponse,
    dependencies=[Depends(require_client_token)],
)
async def legal_query(payload: LegalQueryRequest) -> LegalQueryResponse:
    client: AsyncOpenAI = app.state.openai
    instructions = f"{LEGAL_INSTRUCTIONS}\n\n{_role_context(payload.role)}"

    try:
        response = await client.responses.create(
            model=DEFAULT_MODEL,
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
        model=DEFAULT_MODEL,
        matter_id=payload.matter_id,
    )
