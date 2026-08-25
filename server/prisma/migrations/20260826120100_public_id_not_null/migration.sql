-- Run only after backend/scripts/backfill_public_ids.py has assigned a
-- publicId to every existing row — this will fail if any row is still NULL.
-- AlterTable
ALTER TABLE "User" ALTER COLUMN "publicId" SET NOT NULL;
