-- migration: 20260831120000_word_cards
-- Word-card foundation (§ word cards, 2026-08-31). VocabularyItem already IS
-- the one-per-word "card" (unique id, stored once, never duplicated per
-- lesson/user) - this only extends it with three nullable columns (a photo,
-- a category link, a direct language link) rather than creating a second,
-- parallel word table. Category and UserWordProgress are new, purely
-- additive tables - no existing row, column, or constraint is altered or
-- removed.

-- AlterTable
ALTER TABLE "VocabularyItem" ADD COLUMN "imageUrl" TEXT;
ALTER TABLE "VocabularyItem" ADD COLUMN "categoryId" TEXT;
ALTER TABLE "VocabularyItem" ADD COLUMN "languageId" TEXT;

-- CreateIndex (word-card lookups by category/language - § performance, 16)
CREATE INDEX "VocabularyItem_categoryId_idx" ON "VocabularyItem"("categoryId");
CREATE INDEX "VocabularyItem_languageId_idx" ON "VocabularyItem"("languageId");

-- CreateTable
CREATE TABLE "Category" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "nameKey" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Category_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Category_nameKey_key" ON "Category"("nameKey");

-- CreateTable
CREATE TABLE "UserWordProgress" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "wordId" TEXT NOT NULL,
    "learnedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UserWordProgress_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "UserWordProgress_userId_wordId_key" ON "UserWordProgress"("userId", "wordId");

-- CreateIndex (reverse lookup - "who has learned word X", and the FK column alone)
CREATE INDEX "UserWordProgress_wordId_idx" ON "UserWordProgress"("wordId");

-- AddForeignKey
ALTER TABLE "UserWordProgress" ADD CONSTRAINT "UserWordProgress_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UserWordProgress" ADD CONSTRAINT "UserWordProgress_wordId_fkey" FOREIGN KEY ("wordId") REFERENCES "VocabularyItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Backfill: existing words get a real languageId instead of staying null.
-- Course-linked words derive it from their own Course -> Level chain;
-- legacy words (courseId = 'legacy', no Course/Level row to walk through)
-- get German's id - the same "legacy = German" convention
-- get_total_time_seconds (app/services/progress.py) already relies on.
UPDATE "VocabularyItem" vi
SET "languageId" = lvl."languageId"
FROM "Course" c
JOIN "Level" lvl ON lvl."id" = c."levelId"
WHERE vi."courseId" = c."id" AND vi."languageId" IS NULL;

UPDATE "VocabularyItem"
SET "languageId" = (SELECT "id" FROM "Language" WHERE lower(trim("name")) = 'немецкий' LIMIT 1)
WHERE "courseId" = 'legacy' AND "languageId" IS NULL;
