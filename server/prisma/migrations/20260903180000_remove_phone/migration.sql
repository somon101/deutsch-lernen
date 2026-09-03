-- migration: 20260903180000_remove_phone
-- Phone is not used anywhere on the platform any more
-- (§ security & privacy rework, 2026-09-03). Full removal, not a hide: the
-- column and every stored value go. DROP COLUMN discards the column's data
-- along with the column itself, so there is no separate "wipe the values
-- first" step — nothing survives a dropped column.
--
-- IF EXISTS makes this safe to run more than once (see
-- backend/app/services/schema_bootstrap.py's ensure_phone_removed, which
-- runs this same statement at every app startup since nothing in the
-- deploy pipeline runs `prisma migrate`).

ALTER TABLE "User" DROP COLUMN IF EXISTS "phone";
