-- The node-flow canvas feature this column was added for was reverted; the
-- Role.TEACHER value from the same original migration stays (that part is
-- being kept). Any saved layout data was purely presentational scratch data
-- from the reverted editor, never read by any other part of the app.

-- AlterTable
ALTER TABLE "CourseLesson" DROP COLUMN "canvasLayout";

-- AlterTable
ALTER TABLE "LessonContent" DROP COLUMN "canvasLayout";
