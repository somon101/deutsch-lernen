-- migration: 20260915100000_streak_reminder
-- Streak-at-risk push reminder — admin-gated, server/push only, fully
-- independent from the (now locally-delivered) lesson/study reminder
-- (§ streak reminder, 2026-09-15).

-- AlterTable
ALTER TABLE "NotificationSettings" ADD COLUMN IF NOT EXISTS "streakReminderEnabled" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE IF NOT EXISTS "StreakReminderLog" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "reminderDate" DATE NOT NULL,
    "sendCount" INTEGER NOT NULL DEFAULT 1,
    "lastSentAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "StreakReminderLog_pkey" PRIMARY KEY ("id")
);

-- At most one row per user per (UTC) day — the whole "don't double-send"
-- guarantee, same shape as LessonReminderLog/DailyGoalAward.
CREATE UNIQUE INDEX IF NOT EXISTS "StreakReminderLog_userId_reminderDate_key" ON "StreakReminderLog"("userId", "reminderDate");

-- AddForeignKey
DO $$ BEGIN
    ALTER TABLE "StreakReminderLog" ADD CONSTRAINT "StreakReminderLog_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
