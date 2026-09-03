"""Creates the daily-goal tables if they are not there yet
(§ daily goal, 2026-09-03).

The schema of record lives in server/prisma/migrations/, and the migration
for these two tables is committed there. But nothing in the deploy pipeline
runs `prisma migrate`, so a migration only reaches the database when someone
applies it by hand — and until then the feature is broken in production
rather than merely unbuilt.

So this runs the same CREATE TABLE IF NOT EXISTS at startup, next to the
`ensure_admin_exists` and `ensure_storage_bucket` the app already performs.
It is idempotent, safe to run from several instances at once, and additive
only: it can bring a missing table into being, never alter or drop one.
Anything beyond adding a table still needs the real migration.

It must never prevent the service from starting. If the database role has no
DDL rights, the failure is logged and the app comes up — with the daily goal
returning errors, which is a far better outcome than an API that will not
boot at all.
"""

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

# Kept byte-for-byte in step with
# server/prisma/migrations/20260903100000_daily_goal/migration.sql.
_STATEMENTS = (
    """
    CREATE TABLE IF NOT EXISTS "UserPreference" (
        "id" TEXT NOT NULL,
        "userId" TEXT NOT NULL,
        "dailyGoalMinutes" INTEGER NOT NULL DEFAULT 10,
        "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT "UserPreference_pkey" PRIMARY KEY ("id")
    )
    """,
    'CREATE UNIQUE INDEX IF NOT EXISTS "UserPreference_userId_key" ON "UserPreference"("userId")',
    # Sound settings (§ sound settings, 2026-09-03) — added to the existing
    # preferences row rather than to a table of their own.
    'ALTER TABLE "UserPreference" ADD COLUMN IF NOT EXISTS "lessonSoundEnabled" BOOLEAN NOT NULL DEFAULT true',
    'ALTER TABLE "UserPreference" ADD COLUMN IF NOT EXISTS "wordAudioEnabled" BOOLEAN NOT NULL DEFAULT true',
    """
    CREATE TABLE IF NOT EXISTS "DailyGoalAward" (
        "id" TEXT NOT NULL,
        "userId" TEXT NOT NULL,
        "awardDate" DATE NOT NULL,
        "goalMinutes" INTEGER NOT NULL,
        "points" INTEGER NOT NULL,
        "secondsAtAward" INTEGER NOT NULL,
        "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT "DailyGoalAward_pkey" PRIMARY KEY ("id")
    )
    """,
    # The index the "reward paid once per day" guarantee rests on. Created
    # separately from the table so an existing table still gains it.
    'CREATE UNIQUE INDEX IF NOT EXISTS "DailyGoalAward_userId_awardDate_key" ON "DailyGoalAward"("userId", "awardDate")',
    """
    DO $$ BEGIN
        ALTER TABLE "UserPreference" ADD CONSTRAINT "UserPreference_userId_fkey"
            FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    EXCEPTION WHEN duplicate_object THEN NULL; END $$
    """,
    """
    DO $$ BEGIN
        ALTER TABLE "DailyGoalAward" ADD CONSTRAINT "DailyGoalAward_userId_fkey"
            FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    EXCEPTION WHEN duplicate_object THEN NULL; END $$
    """,
)


async def ensure_daily_goal_tables(db: AsyncSession) -> None:
    for statement in _STATEMENTS:
        try:
            await db.execute(text(statement))
            await db.commit()
        except Exception as exc:  # noqa: BLE001 — startup must survive anything here
            await db.rollback()
            print(f"ensure_daily_goal_tables: не удалось выполнить DDL ({type(exc).__name__}: {exc})")


# Kept byte-for-byte in step with
# server/prisma/migrations/20260903150000_lesson_graph/migration.sql.
_LESSON_GRAPH_STATEMENTS = (
    """
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
    )
    """,
    'CREATE INDEX IF NOT EXISTS "LessonNode_lessonId_idx" ON "LessonNode"("lessonId")',
    """
    CREATE TABLE IF NOT EXISTS "LessonEdge" (
        "id" TEXT NOT NULL,
        "lessonId" TEXT NOT NULL,
        "fromNodeId" TEXT NOT NULL,
        "toNodeId" TEXT NOT NULL,
        "position" INTEGER NOT NULL DEFAULT 0,
        "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT "LessonEdge_pkey" PRIMARY KEY ("id")
    )
    """,
    'CREATE UNIQUE INDEX IF NOT EXISTS "LessonEdge_fromNodeId_toNodeId_key" ON "LessonEdge"("fromNodeId", "toNodeId")',
    'CREATE INDEX IF NOT EXISTS "LessonEdge_lessonId_idx" ON "LessonEdge"("lessonId")',
    'CREATE INDEX IF NOT EXISTS "LessonEdge_fromNodeId_idx" ON "LessonEdge"("fromNodeId")',
    'CREATE INDEX IF NOT EXISTS "LessonEdge_toNodeId_idx" ON "LessonEdge"("toNodeId")',
    'ALTER TABLE "LessonState" ADD COLUMN IF NOT EXISTS "nodeResults" JSONB',
)


async def ensure_lesson_graph_tables(db: AsyncSession) -> None:
    for statement in _LESSON_GRAPH_STATEMENTS:
        try:
            await db.execute(text(statement))
            await db.commit()
        except Exception as exc:  # noqa: BLE001 — startup must survive anything here
            await db.rollback()
            print(f"ensure_lesson_graph_tables: не удалось выполнить DDL ({type(exc).__name__}: {exc})")


# Kept byte-for-byte in step with
# server/prisma/migrations/20260903180000_remove_phone/migration.sql.
#
# Phone is gone from the platform entirely (§ security & privacy rework,
# 2026-09-03) — confirmed via a full grep of both frontend and backend before
# removing it, so this DROP is not a guess. DROP COLUMN discards the stored
# values along with the column, so there is no separate step to wipe them.
# IF EXISTS makes re-running this at every startup harmless once the column
# is already gone.
_REMOVE_PHONE_STATEMENTS = ('ALTER TABLE "User" DROP COLUMN IF EXISTS "phone"',)


async def ensure_phone_removed(db: AsyncSession) -> None:
    for statement in _REMOVE_PHONE_STATEMENTS:
        try:
            await db.execute(text(statement))
            await db.commit()
        except Exception as exc:  # noqa: BLE001 — startup must survive anything here
            await db.rollback()
            print(f"ensure_phone_removed: не удалось выполнить DDL ({type(exc).__name__}: {exc})")


# Kept byte-for-byte in step with
# server/prisma/migrations/20260904090000_course_content_language/migration.sql.
#
# Eight new, purely-additive child tables (§ course content language,
# 2026-09-04) — one per existing content entity whose learner-facing text
# now has an instructional-language ("ru"/"tg", extensible) variant, keyed
# by a `locale` column rather than one column per language (see
# CourseTranslation's docstring for why). None of this alters or drops an
# existing column; every parent row keeps working exactly as before for any
# reader that hasn't been updated to look at these tables yet.
_CONTENT_LOCALE_STATEMENTS = (
    """
    CREATE TABLE IF NOT EXISTS "CourseTranslation" (
        "id" TEXT NOT NULL,
        "courseId" TEXT NOT NULL,
        "locale" TEXT NOT NULL,
        "title" TEXT NOT NULL,
        "description" TEXT NOT NULL DEFAULT '',
        "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updatedAt" TIMESTAMP(3) NOT NULL,
        CONSTRAINT "CourseTranslation_pkey" PRIMARY KEY ("id")
    )
    """,
    'CREATE UNIQUE INDEX IF NOT EXISTS "CourseTranslation_courseId_locale_key" ON "CourseTranslation"("courseId", "locale")',
    """
    DO $$ BEGIN
        ALTER TABLE "CourseTranslation" ADD CONSTRAINT "CourseTranslation_courseId_fkey"
            FOREIGN KEY ("courseId") REFERENCES "Course"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    EXCEPTION WHEN duplicate_object THEN NULL; END $$
    """,
    """
    CREATE TABLE IF NOT EXISTS "CourseLessonTranslation" (
        "id" TEXT NOT NULL,
        "courseLessonId" TEXT NOT NULL,
        "locale" TEXT NOT NULL,
        "title" TEXT NOT NULL,
        "description" TEXT NOT NULL DEFAULT '',
        "materialText" TEXT NOT NULL DEFAULT '',
        "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updatedAt" TIMESTAMP(3) NOT NULL,
        CONSTRAINT "CourseLessonTranslation_pkey" PRIMARY KEY ("id")
    )
    """,
    'CREATE UNIQUE INDEX IF NOT EXISTS "CourseLessonTranslation_courseLessonId_locale_key" ON "CourseLessonTranslation"("courseLessonId", "locale")',
    """
    DO $$ BEGIN
        ALTER TABLE "CourseLessonTranslation" ADD CONSTRAINT "CourseLessonTranslation_courseLessonId_fkey"
            FOREIGN KEY ("courseLessonId") REFERENCES "CourseLesson"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    EXCEPTION WHEN duplicate_object THEN NULL; END $$
    """,
    """
    CREATE TABLE IF NOT EXISTS "VocabularyTranslation" (
        "id" TEXT NOT NULL,
        "vocabularyItemId" TEXT NOT NULL,
        "locale" TEXT NOT NULL,
        "translation" TEXT NOT NULL,
        "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updatedAt" TIMESTAMP(3) NOT NULL,
        CONSTRAINT "VocabularyTranslation_pkey" PRIMARY KEY ("id")
    )
    """,
    'CREATE UNIQUE INDEX IF NOT EXISTS "VocabularyTranslation_vocabularyItemId_locale_key" ON "VocabularyTranslation"("vocabularyItemId", "locale")',
    """
    DO $$ BEGIN
        ALTER TABLE "VocabularyTranslation" ADD CONSTRAINT "VocabularyTranslation_vocabularyItemId_fkey"
            FOREIGN KEY ("vocabularyItemId") REFERENCES "VocabularyItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    EXCEPTION WHEN duplicate_object THEN NULL; END $$
    """,
    """
    CREATE TABLE IF NOT EXISTS "MaterialTranslation" (
        "id" TEXT NOT NULL,
        "materialId" TEXT NOT NULL,
        "locale" TEXT NOT NULL,
        "title" TEXT NOT NULL,
        "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updatedAt" TIMESTAMP(3) NOT NULL,
        CONSTRAINT "MaterialTranslation_pkey" PRIMARY KEY ("id")
    )
    """,
    'CREATE UNIQUE INDEX IF NOT EXISTS "MaterialTranslation_materialId_locale_key" ON "MaterialTranslation"("materialId", "locale")',
    """
    DO $$ BEGIN
        ALTER TABLE "MaterialTranslation" ADD CONSTRAINT "MaterialTranslation_materialId_fkey"
            FOREIGN KEY ("materialId") REFERENCES "Material"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    EXCEPTION WHEN duplicate_object THEN NULL; END $$
    """,
    """
    CREATE TABLE IF NOT EXISTS "MaterialBlockTranslation" (
        "id" TEXT NOT NULL,
        "materialBlockId" TEXT NOT NULL,
        "locale" TEXT NOT NULL,
        "title" TEXT NOT NULL,
        "content" TEXT NOT NULL,
        "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updatedAt" TIMESTAMP(3) NOT NULL,
        CONSTRAINT "MaterialBlockTranslation_pkey" PRIMARY KEY ("id")
    )
    """,
    'CREATE UNIQUE INDEX IF NOT EXISTS "MaterialBlockTranslation_materialBlockId_locale_key" ON "MaterialBlockTranslation"("materialBlockId", "locale")',
    """
    DO $$ BEGIN
        ALTER TABLE "MaterialBlockTranslation" ADD CONSTRAINT "MaterialBlockTranslation_materialBlockId_fkey"
            FOREIGN KEY ("materialBlockId") REFERENCES "MaterialBlock"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    EXCEPTION WHEN duplicate_object THEN NULL; END $$
    """,
    """
    CREATE TABLE IF NOT EXISTS "QuestionTranslation" (
        "id" TEXT NOT NULL,
        "questionId" TEXT NOT NULL,
        "locale" TEXT NOT NULL,
        "prompt" TEXT,
        "options" TEXT[],
        "correctAnswer" TEXT,
        "data" JSONB,
        "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updatedAt" TIMESTAMP(3) NOT NULL,
        CONSTRAINT "QuestionTranslation_pkey" PRIMARY KEY ("id")
    )
    """,
    'CREATE UNIQUE INDEX IF NOT EXISTS "QuestionTranslation_questionId_locale_key" ON "QuestionTranslation"("questionId", "locale")',
    """
    DO $$ BEGIN
        ALTER TABLE "QuestionTranslation" ADD CONSTRAINT "QuestionTranslation_questionId_fkey"
            FOREIGN KEY ("questionId") REFERENCES "Question"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    EXCEPTION WHEN duplicate_object THEN NULL; END $$
    """,
    """
    CREATE TABLE IF NOT EXISTS "LessonNodeMedia" (
        "id" TEXT NOT NULL,
        "lessonNodeId" TEXT NOT NULL,
        "locale" TEXT NOT NULL,
        "mediaUrl" TEXT NOT NULL,
        "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updatedAt" TIMESTAMP(3) NOT NULL,
        CONSTRAINT "LessonNodeMedia_pkey" PRIMARY KEY ("id")
    )
    """,
    'CREATE UNIQUE INDEX IF NOT EXISTS "LessonNodeMedia_lessonNodeId_locale_key" ON "LessonNodeMedia"("lessonNodeId", "locale")',
    """
    DO $$ BEGIN
        ALTER TABLE "LessonNodeMedia" ADD CONSTRAINT "LessonNodeMedia_lessonNodeId_fkey"
            FOREIGN KEY ("lessonNodeId") REFERENCES "LessonNode"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    EXCEPTION WHEN duplicate_object THEN NULL; END $$
    """,
    """
    CREATE TABLE IF NOT EXISTS "CourseLessonMedia" (
        "id" TEXT NOT NULL,
        "courseLessonId" TEXT NOT NULL,
        "mediaType" TEXT NOT NULL,
        "locale" TEXT NOT NULL,
        "url" TEXT NOT NULL,
        "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updatedAt" TIMESTAMP(3) NOT NULL,
        CONSTRAINT "CourseLessonMedia_pkey" PRIMARY KEY ("id")
    )
    """,
    'CREATE UNIQUE INDEX IF NOT EXISTS "CourseLessonMedia_courseLessonId_mediaType_locale_key" ON "CourseLessonMedia"("courseLessonId", "mediaType", "locale")',
    """
    DO $$ BEGIN
        ALTER TABLE "CourseLessonMedia" ADD CONSTRAINT "CourseLessonMedia_courseLessonId_fkey"
            FOREIGN KEY ("courseLessonId") REFERENCES "CourseLesson"("id") ON DELETE CASCADE ON UPDATE CASCADE;
    EXCEPTION WHEN duplicate_object THEN NULL; END $$
    """,
    # Per-user choice of which locale a course's own text/media is shown in
    # — see app/services/content_locale.py's module docstring for why this
    # is not a Language row. Nullable, no FK (validated app-side against
    # SUPPORTED_CONTENT_LOCALES), same shape as the pre-existing
    # selectedLanguageId column it sits next to.
    'ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "contentLocale" TEXT',
)


async def ensure_content_locale_tables(db: AsyncSession) -> None:
    for statement in _CONTENT_LOCALE_STATEMENTS:
        try:
            await db.execute(text(statement))
            await db.commit()
        except Exception as exc:  # noqa: BLE001 — startup must survive anything here
            await db.rollback()
            print(f"ensure_content_locale_tables: не удалось выполнить DDL ({type(exc).__name__}: {exc})")
