-- Admin-editable course content (override layer over the file-based lessons).

CREATE TABLE "LessonContent" (
    "lessonId" TEXT NOT NULL,
    "materialText" TEXT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "updatedById" TEXT,

    CONSTRAINT "LessonContent_pkey" PRIMARY KEY ("lessonId")
);

CREATE TABLE "VocabularyItem" (
    "id" TEXT NOT NULL,
    "lessonId" TEXT NOT NULL,
    "german" TEXT NOT NULL,
    "translation" TEXT NOT NULL,
    "pronunciation" TEXT,
    "position" INTEGER NOT NULL,

    CONSTRAINT "VocabularyItem_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "LessonQuestion" (
    "id" TEXT NOT NULL,
    "lessonId" TEXT NOT NULL,
    "setName" TEXT NOT NULL,
    "prompt" TEXT NOT NULL,
    "options" TEXT[],
    "correctAnswer" TEXT NOT NULL,
    "position" INTEGER NOT NULL,

    CONSTRAINT "LessonQuestion_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "VocabularyItem_lessonId_position_idx" ON "VocabularyItem"("lessonId", "position");
CREATE INDEX "LessonQuestion_lessonId_setName_position_idx" ON "LessonQuestion"("lessonId", "setName", "position");
