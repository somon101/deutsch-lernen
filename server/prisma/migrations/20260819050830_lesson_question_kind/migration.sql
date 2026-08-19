-- AlterTable
ALTER TABLE "LessonQuestion" ADD COLUMN     "data" JSONB,
ADD COLUMN     "kind" TEXT NOT NULL DEFAULT 'choice';
