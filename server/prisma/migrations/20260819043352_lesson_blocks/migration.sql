-- Named question blocks inside a stage, so a built lesson can hold several
-- mini-tests (or practice/review blocks) without changing the stage sequence
-- the learner walks through.

CREATE TABLE "LessonBlock" (
    "id" TEXT NOT NULL,
    "courseId" TEXT NOT NULL,
    "lessonId" TEXT NOT NULL,
    "stage" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "position" INTEGER NOT NULL,

    CONSTRAINT "LessonBlock_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "LessonBlock_lessonId_stage_position_idx" ON "LessonBlock"("lessonId", "stage", "position");

-- Existing questions keep blockId NULL: the file-based course has one
-- unnamed set per stage and is unaffected.
ALTER TABLE "LessonQuestion" ADD COLUMN "blockId" TEXT;
CREATE INDEX "LessonQuestion_blockId_position_idx" ON "LessonQuestion"("blockId", "position");
