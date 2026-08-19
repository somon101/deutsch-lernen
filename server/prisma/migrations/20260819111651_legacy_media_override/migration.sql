-- AlterTable
ALTER TABLE "LessonContent" ADD COLUMN     "audioUrl" TEXT,
ADD COLUMN     "videoUrl" TEXT,
ALTER COLUMN "materialText" DROP NOT NULL;
