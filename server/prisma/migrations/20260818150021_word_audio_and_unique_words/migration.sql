-- Per-word recorded pronunciation, plus a course-wide uniqueness key so the
-- same word cannot be added to two different lessons.

ALTER TABLE "VocabularyItem" ADD COLUMN "audioUrl" TEXT;

-- Nullable first so existing rows survive, then backfilled and locked down.
ALTER TABLE "VocabularyItem" ADD COLUMN "germanKey" TEXT;

-- Same normalisation the server applies: lower-cased, without the
-- punctuation that does not distinguish one word from another.
UPDATE "VocabularyItem"
SET "germanKey" = btrim(regexp_replace(lower("german"), '[.,!?;:…"''«»„“”()]', '', 'g'));

-- Keep only the first occurrence of any duplicate so the constraint can apply.
DELETE FROM "VocabularyItem" a
USING "VocabularyItem" b
WHERE a."germanKey" = b."germanKey" AND a.ctid > b.ctid;

ALTER TABLE "VocabularyItem" ALTER COLUMN "germanKey" SET NOT NULL;

CREATE UNIQUE INDEX "VocabularyItem_germanKey_key" ON "VocabularyItem"("germanKey");
