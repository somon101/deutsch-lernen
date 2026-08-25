from datetime import datetime, timezone

# All timestamp columns in the existing Postgres DB are "timestamp without
# time zone" (Prisma's default DateTime mapping) but are conceptually always
# UTC — Prisma/Node write and read them as UTC Date objects. SQLAlchemy
# returns them as naive datetimes, so every write must use naive UTC "now",
# and every read serialized to JSON must get its "Z" suffix put back on
# manually to match the shape the old Express API already produced
# (JS's Date.toISOString() always includes "Z").


def utcnow() -> datetime:
    return datetime.utcnow()


def to_iso_z(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    return dt.isoformat(timespec="milliseconds") + "Z"


def from_iso(value: str | None) -> datetime | None:
    """Parses an ISO 8601 string (as sent by the client, e.g.
    "2026-01-01T00:00:00.000Z") into a naive UTC datetime for storage —
    mirrors `new Date(value)` followed by storing into a tz-naive column."""
    if value is None:
        return None
    dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt
