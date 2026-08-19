-- Course builder: courses created from scratch in the admin panel.
-- The original file-based course keeps working untouched; its existing rows
-- are simply labelled with the reserved courseId "legacy".

CREATE TYPE "CourseStatus" AS ENUM ('DRAFT', 'PUBLISHED');

CREATE TABLE "Course" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "coverUrl" TEXT,
    "status" "CourseStatus" NOT NULL DEFAULT 'DRAFT',
    "position" INTEGER NOT NULL,
    "createdById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Course_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "CourseLesson" (
    "id" TEXT NOT NULL,
    "courseId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "materialText" TEXT NOT NULL DEFAULT '',
    "videoUrl" TEXT,
    "audioUrl" TEXT,
    "position" INTEGER NOT NULL,

    CONSTRAINT "CourseLesson_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "CourseLesson_courseId_position_idx" ON "CourseLesson"("courseId", "position");

ALTER TABLE "CourseLesson" ADD CONSTRAINT "CourseLesson_courseId_fkey"
    FOREIGN KEY ("courseId") REFERENCES "Course"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Words and questions now belong to a course. Everything that exists today is
-- part of the original file-based course.
ALTER TABLE "VocabularyItem" ADD COLUMN "courseId" TEXT NOT NULL DEFAULT 'legacy';
ALTER TABLE "LessonQuestion" ADD COLUMN "courseId" TEXT NOT NULL DEFAULT 'legacy';

-- A word must stay unique inside its own course, but separate courses are
-- independent and may each use the same word.
DROP INDEX IF EXISTS "VocabularyItem_germanKey_key";
CREATE UNIQUE INDEX "VocabularyItem_courseId_germanKey_key"
    ON "VocabularyItem"("courseId", "germanKey");
