-- migration: 20260829220000_streak_mode
-- Adds calendar-day granularity to ActivityTime (needed to answer "how much
-- time on day X", which the table couldn't answer before — its all-time
-- totals are unaffected, since they're just a SUM across every day now
-- instead of the one running total before) and a new DailyActivity table:
-- one row per (user, activityType, day), the discrete "a qualifying
-- activity happened" signal streaks/weekly-activity are built from
-- (§ streak mode, 2026-08-29).

-- AlterTable: give ActivityTime a day dimension
ALTER TABLE "ActivityTime" ADD COLUMN "activityDate" DATE;
UPDATE "ActivityTime" SET "activityDate" = CURRENT_DATE WHERE "activityDate" IS NULL;
ALTER TABLE "ActivityTime" ALTER COLUMN "activityDate" SET NOT NULL;

DROP INDEX IF EXISTS "ActivityTime_userId_lessonId_activityType_key";
CREATE UNIQUE INDEX "ActivityTime_userId_lessonId_activityType_activityDate_key" ON "ActivityTime"("userId", "lessonId", "activityType", "activityDate");

-- CreateTable
CREATE TABLE "DailyActivity" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "activityType" TEXT NOT NULL,
    "activityDate" DATE NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DailyActivity_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "DailyActivity_userId_activityType_activityDate_key" ON "DailyActivity"("userId", "activityType", "activityDate");

-- AddForeignKey
ALTER TABLE "DailyActivity" ADD CONSTRAINT "DailyActivity_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
