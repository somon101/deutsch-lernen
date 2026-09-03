"""Creates the daily-goal tables if they are not there yet
(§ daily goal, 2026-09-03).

The schema of record lives in server/prisma/migrations/, and the migration
for these two tables is committed there. But nothing in the deploy pipeline
runs `prisma migrate`, so a migration only reaches the database when someone
applies it by hand — and until then the feature is broken in production
rather than merely unbuilt.

So this runs the same CREATE TABLE IF NOT EXISTS at startup, next to the
`ensure_admin_exists` and `ensure_storage_bucket` the app already performs.
It is idempotent, safe to run from several instances at once, and additive
only: it can bring a missing table into being, never alter or drop one.
Anything beyond adding a table still needs the real migration.

It must never prevent the service from starting. If the database role has no
DDL rights, the failure is logged and the app comes up — with the daily goal
returning errors, which is a far better outcome than an API that will not
boot at all.
"""

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

# Kept byte-for-byte in step with
# server/prisma/migrations/20260903100000_daily_goal/migration.sql.
_STATEMENTS = (
    """
    CREATE TABLE IF NOT EXISTS "UserPreference" (
        "id" TEXT NOT NULL,
        "userId" TEXT NOT NULL,
        "dailyGoalMinutes" INTEGER NOT NULL DEFAULT 10,
        "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT "UserPreference_pkey" PRIMARY KEY ("id")
    )
    """,
    'CREATE UNIQUE INDEX IF NOT EXISTS "UserPreference_userId_key" ON "UserPreference"("userId")',
    # Sound settings (§ sound settings, 2026-09-03) — added to the existing
    # preferences row rather than to a table of their own.
    'ALTER TABLE "UserPreference" ADD COLUMN IF NOT EXISTS "lessonSoundEnabled" BOOLEAN NOT NULL DEFAULT true',
    'ALTER TABLE "UserPreference" ADD COLUMN IF NOT EXISTS "wordAudioEnabled" BOOLEAN NOT NULL DEFAULT true',
    """
    CREATE TABLE IF NOT EXISTS "DailyGoalAward" (
        "id" TEXT NOT NULL,
        "userId" TEXT NOT NULL,
        "awardDate" DATE NOT NULL,
        "goalMinutes" INTEGER NOT NULL,
        "points" INTEGER NOT NULL,
        "secondsAtAward" INTEGER NOT NULL,
        "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT "DailyGoalAward_pkey" PRIMARY KEY ("id")
    )
    """,
    # The index the "reward paid once per day" guarantee rests on. Created
    # separately from the table so an existing table still gains it.
    'CREATE UNIQUE INDEX IF NOT EXISTS "DailyGoalAward_userId_awardDate_key" ON "DailyGoalAward"("userId", "awardDate")',
    """
    DO $$ BEGIN
        ALTER TABLE "UserPreference" ADD CONSTRAINT "UserPreference_userId_fkey"
            FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    EXCEPTION WHEN duplicate_object THEN NULL; END $$
    """,
    """
    DO $$ BEGIN
        ALTER TABLE "DailyGoalAward" ADD CONSTRAINT "DailyGoalAward_userId_fkey"
            FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    EXCEPTION WHEN duplicate_object THEN NULL; END $$
    """,
)


async def ensure_daily_goal_tables(db: AsyncSession) -> None:
    for statement in _STATEMENTS:
        try:
            await db.execute(text(statement))
            await db.commit()
        except Exception as exc:  # noqa: BLE001 — startup must survive anything here
            await db.rollback()
            print(f"ensure_daily_goal_tables: не удалось выполнить DDL ({type(exc).__name__}: {exc})")
