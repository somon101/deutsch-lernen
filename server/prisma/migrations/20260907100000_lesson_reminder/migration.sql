-- migration: 20260907100000_lesson_reminder
-- Lesson-reminder push, actually wired up (§ lesson reminder fix, 2026-09-07).
--
-- The reminder toggle/time picker in Settings existed already, but wrote
-- only to the device's own SharedPreferences — nothing server-side ever
-- knew a reminder time had been set, so nothing could ever send one. This
-- adds the missing server-side half onto the existing UserPreference row
-- (pushEnabled/lessonReminderEnabled/lessonReminderHour/lessonReminderMinute/
-- timezone), plus LessonReminderLog for the "at most one first reminder,
-- then repeats no more than every 2 hours, per user per local day" guarantee
-- — the same UNIQUE-index-as-idempotency-mechanism DailyGoalAward already
-- uses for its own "paid at most once per day" promise.

-- AlterTable
ALTER TABLE "UserPreference" ADD COLUMN IF NOT EXISTS "pushEnabled" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "UserPreference" ADD COLUMN IF NOT EXISTS "lessonReminderEnabled" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "UserPreference" ADD COLUMN IF NOT EXISTS "lessonReminderHour" INTEGER NOT NULL DEFAULT 19;
ALTER TABLE "UserPreference" ADD COLUMN IF NOT EXISTS "lessonReminderMinute" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "UserPreference" ADD COLUMN IF NOT EXISTS "timezone" TEXT;

-- CreateTable
CREATE TABLE IF NOT EXISTS "LessonReminderLog" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "reminderDate" DATE NOT NULL,
    "sendCount" INTEGER NOT NULL DEFAULT 1,
    "lastSentAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LessonReminderLog_pkey" PRIMARY KEY ("id")
);

-- At most one row per user per local reminder-day — the whole "don't
-- double-send" guarantee, same shape as DailyGoalAward_userId_awardDate_key.
CREATE UNIQUE INDEX IF NOT EXISTS "LessonReminderLog_userId_reminderDate_key" ON "LessonReminderLog"("userId", "reminderDate");

-- AddForeignKey
DO $$ BEGIN
    ALTER TABLE "LessonReminderLog" ADD CONSTRAINT "LessonReminderLog_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
