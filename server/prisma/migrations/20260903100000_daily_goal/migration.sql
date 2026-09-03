-- migration: 20260903100000_daily_goal
-- The daily study goal (§ daily goal, 2026-09-03).
--
-- Two tables, because the feature needs two different things stored:
--
-- UserPreference is the first server-side home for a user setting at all —
-- until now the settings screen wrote only to the device's own
-- SharedPreferences, so a choice never followed the account to another
-- device. Deliberately one row per user rather than a key/value bag: there
-- is exactly one preference today, and a typed column is both cheaper to
-- query and impossible to fill with a value the schema doesn't know.
--
-- DailyGoalAward records that a day's reward has been paid. The UNIQUE on
-- (userId, awardDate) is the whole idempotency mechanism: two concurrent
-- requests, two devices, a page refresh and a replayed API call all collapse
-- onto the same row, and the second writer is rejected by Postgres rather
-- than by a check in application code that a race could slip past.

-- CreateTable
CREATE TABLE IF NOT EXISTS "UserPreference" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "dailyGoalMinutes" INTEGER NOT NULL DEFAULT 10,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UserPreference_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "UserPreference_userId_key" ON "UserPreference"("userId");

-- CreateTable
CREATE TABLE IF NOT EXISTS "DailyGoalAward" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "awardDate" DATE NOT NULL,
    "goalMinutes" INTEGER NOT NULL,
    "points" INTEGER NOT NULL,
    "secondsAtAward" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DailyGoalAward_pkey" PRIMARY KEY ("id")
);

-- The reward is paid at most once per user per calendar day. Everything the
-- feature promises about "no double reward" rests on this one index.
CREATE UNIQUE INDEX IF NOT EXISTS "DailyGoalAward_userId_awardDate_key" ON "DailyGoalAward"("userId", "awardDate");

-- AddForeignKey
DO $$ BEGIN
    ALTER TABLE "UserPreference" ADD CONSTRAINT "UserPreference_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    ALTER TABLE "DailyGoalAward" ADD CONSTRAINT "DailyGoalAward_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
