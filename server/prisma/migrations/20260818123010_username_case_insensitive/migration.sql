-- Case-insensitive uniqueness for usernames.
-- `username` keeps whatever casing the account was created with (for
-- display); `usernameLower` carries the unique constraint so "Ivan" and
-- "ivan" can never both exist.

-- 1. Add nullable first, so existing rows are not rejected.
ALTER TABLE "User" ADD COLUMN "usernameLower" TEXT;

-- 2. Backfill from the existing usernames.
UPDATE "User" SET "usernameLower" = LOWER("username");

-- 3. Now that every row has a value, make it required.
ALTER TABLE "User" ALTER COLUMN "usernameLower" SET NOT NULL;

-- 4. Enforce uniqueness at the database level.
CREATE UNIQUE INDEX "User_usernameLower_key" ON "User"("usernameLower");
