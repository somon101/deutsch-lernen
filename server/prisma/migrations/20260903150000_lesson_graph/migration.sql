-- migration: 20260903150000_lesson_graph
-- Lesson graph (§ lesson graph, 2026-09-03) — replaces the fixed 8-stage
-- sequence with a free-form graph. Additive only: two new tables, one new
-- nullable column on the existing LessonState table. A lesson with no
-- LessonNode rows is unconverted and every existing lesson/read/write path
-- for it is completely unaffected by this migration.

-- CreateTable
CREATE TABLE IF NOT EXISTS "LessonNode" (
    "id" TEXT NOT NULL,
    "courseId" TEXT NOT NULL,
    "lessonId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "refId" TEXT,
    "mediaUrl" TEXT,
    "title" TEXT,
    "posX" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "posY" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "LessonNode_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "LessonNode_lessonId_idx" ON "LessonNode"("lessonId");

-- CreateTable
CREATE TABLE IF NOT EXISTS "LessonEdge" (
    "id" TEXT NOT NULL,
    "lessonId" TEXT NOT NULL,
    "fromNodeId" TEXT NOT NULL,
    "toNodeId" TEXT NOT NULL,
    "position" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LessonEdge_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "LessonEdge_fromNodeId_toNodeId_key" ON "LessonEdge"("fromNodeId", "toNodeId");
CREATE INDEX IF NOT EXISTS "LessonEdge_lessonId_idx" ON "LessonEdge"("lessonId");
CREATE INDEX IF NOT EXISTS "LessonEdge_fromNodeId_idx" ON "LessonEdge"("fromNodeId");
CREATE INDEX IF NOT EXISTS "LessonEdge_toNodeId_idx" ON "LessonEdge"("toNodeId");

-- AlterTable
ALTER TABLE "LessonState" ADD COLUMN IF NOT EXISTS "nodeResults" JSONB;
