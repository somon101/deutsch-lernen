from collections.abc import AsyncGenerator
from urllib.parse import urlsplit, urlunsplit

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.config import settings


def _to_asyncpg_url(url: str) -> str:
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
    scheme = "postgresql" if parts.scheme == "postgres" else parts.scheme
    return urlunsplit((f"{scheme}+asyncpg", parts.netloc, parts.path, "", parts.fragment))


_async_url = _to_asyncpg_url(settings.database_url)

# Node's pg driver (via Prisma) sets the session timezone to UTC by default;
# asyncpg does not, and inherits whatever the Postgres server's own default
# is instead. Since every "timestamp without time zone" column in this DB
# relies on DB-side CURRENT_TIMESTAMP for some fields (see the model
# comments), the two backends would otherwise write DIFFERENT wall-clock
# values for the same instant — confirmed empirically: without this,
# LessonAttempt.createdAt came out ~3 hours off from true UTC. Force UTC
# explicitly so both backends agree.
engine = create_async_engine(_async_url, connect_args={"server_settings": {"timezone": "UTC"}})
async_session = async_sessionmaker(engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session() as session:
        yield session
