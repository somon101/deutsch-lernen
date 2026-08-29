import ssl
from collections.abc import AsyncGenerator
from urllib.parse import parse_qs, urlsplit, urlunsplit

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.config import settings


def _to_asyncpg_url(url: str) -> tuple[str, dict]:
    # Prisma's DATABASE_URL uses the plain "postgresql://" scheme; asyncpg
    # needs the "+asyncpg" driver marker. Same connection string, same
    # database. Prisma's "?schema=public" query param is its own convention
    # (search_path selection) — asyncpg's connect() doesn't accept a
    # "schema" kwarg at all, so it must be stripped; the default schema is
    # already "public" on both sides, so dropping it changes nothing.
    # Some hosts (Render among them) hand out the older "postgres://"
    # scheme rather than "postgresql://" — SQLAlchemy only registers the
    # asyncpg dialect under "postgresql+asyncpg", so "postgres+asyncpg"
    # would fail to resolve at all. Normalize before appending the driver.
    parts = urlsplit(url)
    query = {k.lower(): v[-1] for k, v in parse_qs(parts.query).items() if v}
    scheme = "postgresql" if parts.scheme == "postgres" else parts.scheme
    if scheme.endswith("+asyncpg"):
        scheme = scheme[: -len("+asyncpg")]
    async_url = urlunsplit((f"{scheme}+asyncpg", parts.netloc, parts.path, "", parts.fragment))

    host = (parts.hostname or "").lower()
    sslmode = query.get("sslmode", "")
    use_ssl = sslmode in {"require", "verify-full", "verify-ca"} or "supabase.co" in host
    # Transaction-mode PgBouncer (Supabase pooler port 6543) cannot use
    # asyncpg's prepared-statement cache.
    use_pooler = (
        parts.port == 6543
        or "pooler.supabase.com" in host
        or query.get("pgbouncer", "").lower() in {"true", "1"}
    )

    connect_args: dict = {"server_settings": {"timezone": "UTC"}}
    if use_ssl:
        # Bare ssl=True makes asyncpg demand a fully verifiable CA chain;
        # Supabase's pooler chain fails that check from some networks
        # (Cloud Run included) with "self-signed certificate in certificate
        # chain" even though the connection is genuinely TLS-encrypted.
        # This matches libpq's sslmode=require: encrypt, don't verify the CA.
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        connect_args["ssl"] = context
    if use_pooler:
        connect_args["statement_cache_size"] = 0

    return async_url, connect_args


_async_url, _connect_args = _to_asyncpg_url(settings.database_url)

# Node's pg driver (via Prisma) sets the session timezone to UTC by default;
# asyncpg does not, and inherits whatever the Postgres server's own default
# is instead. Since every "timestamp without time zone" column in this DB
# relies on DB-side CURRENT_TIMESTAMP for some fields (see the model
# comments), the two backends would otherwise write DIFFERENT wall-clock
# values for the same instant — confirmed empirically: without this,
# LessonAttempt.createdAt came out ~3 hours off from true UTC. Force UTC
# explicitly so both backends agree.
_engine_kwargs: dict = {"connect_args": _connect_args}
if "supabase.co" in (urlsplit(settings.database_url).hostname or "").lower():
    # Free-tier Supabase caps direct connections; keep the pool small and
    # go through the pooler URL in DATABASE_URL.
    _engine_kwargs["pool_size"] = 5
    _engine_kwargs["max_overflow"] = 5

engine = create_async_engine(_async_url, **_engine_kwargs)
async_session = async_sessionmaker(engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session() as session:
        yield session
