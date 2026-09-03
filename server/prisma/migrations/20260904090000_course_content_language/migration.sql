-- migration: 20260904090000_course_content_language
-- Eight new, purely-additive child tables (§ course content language,
-- 2026-09-04) giving every existing learner-facing text/media entity an
-- instructional-language ("ru"/"tg", extensible) variant, keyed by a
-- `locale` column rather than one column per language. Nothing existing is
-- altered or dropped. Kept byte-for-byte in step with
-- backend/app/services/schema_bootstrap.py's ensure_content_locale_tables,
-- which is what actually applies this in production (nothing in the deploy
-- pipeline runs `prisma migrate` — see that module's own docstring).

-- CreateTable
CREATE TABLE "CourseTranslation" (
    "id" TEXT NOT NULL,
    "courseId" TEXT NOT NULL,
    "locale" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "CourseTranslation_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "CourseTranslation_courseId_locale_key" ON "CourseTranslation"("courseId", "locale");

-- AddForeignKey
ALTER TABLE "CourseTranslation" ADD CONSTRAINT "CourseTranslation_courseId_fkey" FOREIGN KEY ("courseId") REFERENCES "Course"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- CreateTable
CREATE TABLE "CourseLessonTranslation" (
    "id" TEXT NOT NULL,
    "courseLessonId" TEXT NOT NULL,
    "locale" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "materialText" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "CourseLessonTranslation_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "CourseLessonTranslation_courseLessonId_locale_key" ON "CourseLessonTranslation"("courseLessonId", "locale");

-- AddForeignKey
ALTER TABLE "CourseLessonTranslation" ADD CONSTRAINT "CourseLessonTranslation_courseLessonId_fkey" FOREIGN KEY ("courseLessonId") REFERENCES "CourseLesson"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- CreateTable
CREATE TABLE "VocabularyTranslation" (
    "id" TEXT NOT NULL,
    "vocabularyItemId" TEXT NOT NULL,
    "locale" TEXT NOT NULL,
    "translation" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "VocabularyTranslation_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "VocabularyTranslation_vocabularyItemId_locale_key" ON "VocabularyTranslation"("vocabularyItemId", "locale");

-- AddForeignKey
ALTER TABLE "VocabularyTranslation" ADD CONSTRAINT "VocabularyTranslation_vocabularyItemId_fkey" FOREIGN KEY ("vocabularyItemId") REFERENCES "VocabularyItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- CreateTable
CREATE TABLE "MaterialTranslation" (
    "id" TEXT NOT NULL,
    "materialId" TEXT NOT NULL,
    "locale" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "MaterialTranslation_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "MaterialTranslation_materialId_locale_key" ON "MaterialTranslation"("materialId", "locale");

-- AddForeignKey
ALTER TABLE "MaterialTranslation" ADD CONSTRAINT "MaterialTranslation_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "Material"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- CreateTable
CREATE TABLE "MaterialBlockTranslation" (
    "id" TEXT NOT NULL,
    "materialBlockId" TEXT NOT NULL,
    "locale" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "MaterialBlockTranslation_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "MaterialBlockTranslation_materialBlockId_locale_key" ON "MaterialBlockTranslation"("materialBlockId", "locale");

-- AddForeignKey
ALTER TABLE "MaterialBlockTranslation" ADD CONSTRAINT "MaterialBlockTranslation_materialBlockId_fkey" FOREIGN KEY ("materialBlockId") REFERENCES "MaterialBlock"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- CreateTable
CREATE TABLE "QuestionTranslation" (
    "id" TEXT NOT NULL,
    "questionId" TEXT NOT NULL,
    "locale" TEXT NOT NULL,
    "prompt" TEXT,
    "options" TEXT[],
    "correctAnswer" TEXT,
    "data" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "QuestionTranslation_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "QuestionTranslation_questionId_locale_key" ON "QuestionTranslation"("questionId", "locale");

-- AddForeignKey
ALTER TABLE "QuestionTranslation" ADD CONSTRAINT "QuestionTranslation_questionId_fkey" FOREIGN KEY ("questionId") REFERENCES "Question"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- CreateTable
CREATE TABLE "LessonNodeMedia" (
    "id" TEXT NOT NULL,
    "lessonNodeId" TEXT NOT NULL,
    "locale" TEXT NOT NULL,
    "mediaUrl" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "LessonNodeMedia_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "LessonNodeMedia_lessonNodeId_locale_key" ON "LessonNodeMedia"("lessonNodeId", "locale");

-- AddForeignKey
ALTER TABLE "LessonNodeMedia" ADD CONSTRAINT "LessonNodeMedia_lessonNodeId_fkey" FOREIGN KEY ("lessonNodeId") REFERENCES "LessonNode"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- CreateTable
CREATE TABLE "CourseLessonMedia" (
    "id" TEXT NOT NULL,
    "courseLessonId" TEXT NOT NULL,
    "mediaType" TEXT NOT NULL,
    "locale" TEXT NOT NULL,
    "url" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "CourseLessonMedia_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "CourseLessonMedia_courseLessonId_mediaType_locale_key" ON "CourseLessonMedia"("courseLessonId", "mediaType", "locale");

-- AddForeignKey
ALTER TABLE "CourseLessonMedia" ADD CONSTRAINT "CourseLessonMedia_courseLessonId_fkey" FOREIGN KEY ("courseLessonId") REFERENCES "CourseLesson"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AlterTable
-- Per-user choice of which locale a course's own text/media is shown in —
-- not a Language row (see app/services/content_locale.py), so no FK.
ALTER TABLE "User" ADD COLUMN "contentLocale" TEXT;
