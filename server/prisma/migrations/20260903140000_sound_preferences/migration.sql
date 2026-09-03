-- migration: 20260903140000_sound_preferences
-- The two sound settings (§ sound settings, 2026-09-03).
--
-- Added to UserPreference rather than to a new table: that row already IS
-- "this user's settings", created for the daily goal, and a second settings
-- store beside it would be the parallel system this feature is meant to
-- avoid.
--
-- Two separate columns, deliberately not one "sound on/off". Lesson sounds
-- (right answer, wrong answer, the finishing chime) and word pronunciation
-- are different mechanisms serving different purposes: a learner may well
-- want silence during exercises while still being able to hear how a word
-- is said. Collapsing them would make that impossible and could not be
-- undone later without a data migration.
--
-- Both default to true, which is the behaviour every existing user has now.

ALTER TABLE "UserPreference" ADD COLUMN IF NOT EXISTS "lessonSoundEnabled" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "UserPreference" ADD COLUMN IF NOT EXISTS "wordAudioEnabled" BOOLEAN NOT NULL DEFAULT true;
