-- AlterEnum
ALTER TYPE "Role" ADD VALUE 'TEACHER';

-- AlterTable
ALTER TABLE "CourseLesson" ADD COLUMN     "canvasLayout" JSONB;

-- AlterTable
ALTER TABLE "LessonContent" ADD COLUMN     "canvasLayout" JSONB;
