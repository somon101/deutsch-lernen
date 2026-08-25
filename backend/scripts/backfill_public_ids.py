"""One-time backfill: assigns a unique 9-digit publicId to every existing
User row that doesn't have one yet. Must run after the
20260826120000_add_public_id_nullable migration (adds the nullable, unique
`publicId` column) and before the 20260826120100_public_id_not_null
migration (which requires every row to already be non-null).

Safe to re-run: only rows where publicId IS NULL are touched.

Run from backend/: venv/Scripts/python.exe scripts/backfill_public_ids.py
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import select  # noqa: E402

from app.db import async_session  # noqa: E402
from app.models.user import User  # noqa: E402
from app.services.public_id import generate_public_id  # noqa: E402


async def main() -> None:
    async with async_session() as db:
        result = await db.execute(select(User).where(User.publicId.is_(None)))
        users = result.scalars().all()
        print(f"{len(users)} user(s) missing a publicId")
        for user in users:
            user.publicId = await generate_public_id(db)
            print(f"  {user.username} ({user.id}) -> {user.publicId}")
        await db.commit()
    print("Done.")


if __name__ == "__main__":
    asyncio.run(main())
