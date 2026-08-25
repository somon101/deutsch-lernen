import random

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User

PUBLIC_ID_LENGTH = 9
_MAX_ATTEMPTS = 20


def _random_public_id() -> str:
    """A 9-digit string, leading zeros allowed (it's an opaque identifier,
    not a number) — e.g. "004213087"."""
    return f"{random.randint(0, 10**PUBLIC_ID_LENGTH - 1):0{PUBLIC_ID_LENGTH}d}"


async def generate_public_id(db: AsyncSession) -> str:
    """Collision-checked against the live table, same pattern as
    normalize_username's uniqueness — retried on the rare collision rather
    than trusting randomness alone. 9 digits gives 1e9 possible values, so a
    collision is exceedingly unlikely even at scale, but must still be
    guaranteed, not assumed."""
    for _ in range(_MAX_ATTEMPTS):
        candidate = _random_public_id()
        existing = (await db.execute(select(User.id).where(User.publicId == candidate))).scalar_one_or_none()
        if existing is None:
            return candidate
    raise RuntimeError("Could not generate a unique publicId after several attempts")
