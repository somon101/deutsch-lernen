-- migration: 20260829200000_activity_time
-- Per-(user, lesson, activityType) accumulated seconds (§ time tracking,
-- 2026-08-29) — one row per activity type per lesson, incremented on every
-- client report. Purely additive; no existing table is altered.

-- CreateTable
CREATE TABLE "ActivityTime" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "courseId" TEXT,
    "lessonId" TEXT NOT NULL,
    "activityType" TEXT NOT NULL,
    "seconds" INTEGER NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ActivityTime_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "ActivityTime_userId_lessonId_activityType_key" ON "ActivityTime"("userId", "lessonId", "activityType");

-- AddForeignKey
ALTER TABLE "ActivityTime" ADD CONSTRAINT "ActivityTime_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
