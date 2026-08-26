-- AlterTable
ALTER TABLE "QuestionPlacement" ADD COLUMN     "legacyLessonId" TEXT,
ADD COLUMN     "legacySetName" TEXT;

-- CreateIndex
CREATE INDEX "QuestionPlacement_legacyLessonId_legacySetName_position_idx" ON "QuestionPlacement"("legacyLessonId", "legacySetName", "position");
