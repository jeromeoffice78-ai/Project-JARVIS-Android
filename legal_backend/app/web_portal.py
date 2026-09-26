"""JARVIS mobile-friendly passwordless Chairman web login.

This is a replacement entry point for the broken legacy Vercel password form.
It uses the already-deployed Chairman email verification endpoints and does not
mint bypass tokens, alter user records or embed account credentials in HTML.
"""
from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import FileResponse

router = APIRouter()
_ASSETS = Path(__file__).resolve().parent / "web_portal"
_SECURITY = {
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "X-Frame-Options": "DENY",
    "Cross-Origin-Opener-Policy": "same-origin",
    "Content-Security-Policy": (
        "default-src 'none'; "
        "script-src 'self'; "
        "style-src 'self'; "
        "img-src 'self' data:; "
        "connect-src 'self'; "
        "form-action 'self'; "
        "base-uri 'none'; "
        "frame-ancestors 'none'; "
        "object-src 'none'"
    ),
}


@router.get("/login", include_in_schema=False)
async def passwordless_chairman_login() -> FileResponse:
    return FileResponse(
        _ASSETS / "index.html",
        media_type="text/html; charset=utf-8",
        headers={**_SECURITY, "Cache-Control": "no-store"},
    )


@router.get("/login/app.js", include_in_schema=False)
async def passwordless_chairman_script() -> FileResponse:
    return FileResponse(
        _ASSETS / "app.js",
        media_type="application/javascript; charset=utf-8",
        headers={**_SECURITY, "Cache-Control": "no-store"},
    )


@router.get("/login/app.css", include_in_schema=False)
async def passwordless_chairman_style() -> FileResponse:
    return FileResponse(
        _ASSETS / "app.css",
        media_type="text/css; charset=utf-8",
        headers={**_SECURITY, "Cache-Control": "public, max-age=600"},
    )
