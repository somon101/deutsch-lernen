-- CreateTable
CREATE TABLE "LessonState" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "lessonId" TEXT NOT NULL,
    "completedStages" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "vocabIndex" INTEGER NOT NULL DEFAULT 0,
    "miniTestCorrect" INTEGER,
    "miniTestTotal" INTEGER,
    "miniTestAt" TIMESTAMP(3),
    "practiceCorrect" INTEGER,
    "practiceTotal" INTEGER,
    "practiceAt" TIMESTAMP(3),
    "reviewCorrect" INTEGER,
    "reviewTotal" INTEGER,
    "reviewAt" TIMESTAMP(3),
    "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "LessonState_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "LessonState_userId_lessonId_key" ON "LessonState"("userId", "lessonId");

-- AddForeignKey
ALTER TABLE "LessonState" ADD CONSTRAINT "LessonState_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
