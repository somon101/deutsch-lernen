-- migration: 20260829180000_user_selected_language
-- Per-user language preference for the profile's overall-progress number
-- (§ per-language progress, 2026-08-29). Purely additive, nullable — every
-- existing row defaults to NULL (no language chosen yet).

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "selectedLanguageId" TEXT;

-- AddForeignKey
ALTER TABLE "User" ADD CONSTRAINT "User_selectedLanguageId_fkey" FOREIGN KEY ("selectedLanguageId") REFERENCES "Language"("id") ON DELETE SET NULL ON UPDATE CASCADE;
