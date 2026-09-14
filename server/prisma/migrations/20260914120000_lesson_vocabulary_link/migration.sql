-- migration: 20260914120000_lesson_vocabulary_link
-- Shared dictionary — reuse an existing word in another lesson without
-- copying it (§ shared dictionary, 2026-09-14).
--
-- VocabularyItem.lessonId is untouched by this migration — it stays the
-- word's "home" lesson exactly as before. This table only ADDS extra
-- placements: one row per (lessonId, wordId) means "this lesson also
-- teaches this word," on top of whatever it already natively owns. A
-- lesson that never gets a row here (every lesson that existed before this
-- feature) behaves exactly as it always did.

-- CreateTable
CREATE TABLE IF NOT EXISTS "LessonVocabularyLink" (
    "id" TEXT NOT NULL,
    "lessonId" TEXT NOT NULL,
    "courseId" TEXT NOT NULL,
    "wordId" TEXT NOT NULL,
    "position" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LessonVocabularyLink_pkey" PRIMARY KEY ("id")
);

-- At most one link per (lesson, word) — the whole "don't attach the same
-- word to a lesson twice" guarantee.
CREATE UNIQUE INDEX IF NOT EXISTS "LessonVocabularyLink_lessonId_wordId_key" ON "LessonVocabularyLink"("lessonId", "wordId");
CREATE INDEX IF NOT EXISTS "LessonVocabularyLink_wordId_idx" ON "LessonVocabularyLink"("wordId");
CREATE INDEX IF NOT EXISTS "LessonVocabularyLink_lessonId_idx" ON "LessonVocabularyLink"("lessonId");

-- AddForeignKey
DO $$ BEGIN
    ALTER TABLE "LessonVocabularyLink" ADD CONSTRAINT "LessonVocabularyLink_wordId_fkey"
        FOREIGN KEY ("wordId") REFERENCES "VocabularyItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
