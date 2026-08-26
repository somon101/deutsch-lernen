import re
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from app.config import settings
from app.db import async_session
from app.errors import ApiError
from app.routers import admin, auth, builder, content, learner_courses, me, taxonomy
from app.services.bootstrap import ensure_admin_exists
from app.uploads.storage import UPLOADS_ROOT


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with async_session() as session:
        await ensure_admin_exists(session)
    yield


app = FastAPI(title="Deutsch Lernen API", lifespan=lifespan)

# Mirrors index.ts's custom CORS origin-matching function exactly:
#   1. no Origin header -> allowed (CORSMiddleware doesn't gate non-CORS
#      requests at all, so this is automatic)
#   2. any http://localhost:<port> -> allowed (dev, Vite may pick any port)
#   3. exactly https://localhost / capacitor://localhost -> allowed (the
#      existing Capacitor Android app's bundled-webview origins)
#   4. anything in the CORS_ORIGINS env list -> allowed
_fixed_patterns = [
    r"^http://localhost:\d+$",
    r"^https://localhost$",
    r"^capacitor://localhost$",
    # Cloudflare's free "quick tunnel" hostnames — used to expose a local
    # dev server (web build or the FastAPI backend itself) to a phone on a
    # different network for ad-hoc testing. A new random subdomain each
    # time a tunnel starts, always under this fixed, Cloudflare-owned domain.
    r"^https://[a-z0-9-]+\.trycloudflare\.com$",
]
_env_patterns = [rf"^{re.escape(origin)}$" for origin in settings.cors_origins_list]
_origin_regex = "|".join(_fixed_patterns + _env_patterns)

app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=_origin_regex,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(ApiError)
async def api_error_handler(_request: Request, exc: ApiError) -> JSONResponse:
    return JSONResponse(status_code=exc.status_code, content={"error": exc.message})


@app.exception_handler(Exception)
async def unhandled_error_handler(_request: Request, exc: Exception) -> JSONResponse:
    print(f"Unhandled error: {exc!r}")
    return JSONResponse(status_code=500, content={"error": "Внутренняя ошибка сервера"})


@app.get("/health")
async def health():
    return {"ok": True}


# Same on-disk tree the Express server serves (server/uploads/) — no auth,
# matching index.ts's plain express.static("/uploads") mount exactly.
app.mount("/uploads", StaticFiles(directory=str(UPLOADS_ROOT)), name="uploads")


app.include_router(auth.router)
app.include_router(me.router)
app.include_router(admin.router)
app.include_router(content.router)
app.include_router(builder.router)
app.include_router(learner_courses.router)
app.include_router(taxonomy.router)
