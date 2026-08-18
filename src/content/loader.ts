import { LessonAsset, LessonContent } from "./types";
import { parseVocabulary } from "./parseVocabulary";
import { parseLessonText } from "./parseLessonText";
import { fetchContentOverrides } from "./overrides";

// Content is discovered purely from files on disk under /lessonN (or
// /lesson-N) folders at the project root — adding lesson2/, lesson3/, ...
// with the same file roles is enough to make a new lesson appear, no code
// changes required.

const VIDEO_EXT = new Set(["mp4", "webm", "mov", "mkv", "m4v"]);
const AUDIO_EXT = new Set(["mp3", "wav", "m4a", "ogg", "aac", "flac"]);
const IMAGE_EXT = new Set(["png", "jpg", "jpeg", "gif", "webp", "svg"]);

const VOCAB_HINTS = ["словар", "vocab", "wortschatz"];
const MATERIAL_HINTS = ["урок", "lesson", "material", "материал", "текст", "text"];

function extOf(path: string): string {
  const name = path.split("/").pop() ?? path;
  const dot = name.lastIndexOf(".");
  return dot === -1 ? "" : name.slice(dot + 1).toLowerCase();
}

function baseName(path: string): string {
  return path.split("/").pop() ?? path;
}

function matchesHint(name: string, hints: string[]): boolean {
  const lower = name.toLowerCase();
  return hints.some((h) => lower.includes(h));
}

type Loader = () => Promise<string>;

// Two glob shapes are merged so both "lesson1/file" and "lesson1/sub/file"
// are found regardless of how the bundler's glob engine treats "**".
const rawLoaders: Record<string, Loader> = {
  ...(import.meta.glob("/lesson*/**", { query: "?raw", import: "default" }) as Record<string, Loader>),
  ...(import.meta.glob("/lesson*/*", { query: "?raw", import: "default" }) as Record<string, Loader>),
};

const urlLoaders: Record<string, Loader> = {
  ...(import.meta.glob("/lesson*/**", { query: "?url", import: "default" }) as Record<string, Loader>),
  ...(import.meta.glob("/lesson*/*", { query: "?url", import: "default" }) as Record<string, Loader>),
};

interface DiscoveredLesson {
  id: string;
  files: string[];
}

function discoverLessons(): DiscoveredLesson[] {
  const byLesson = new Map<string, string[]>();
  for (const path of Object.keys(urlLoaders)) {
    const match = path.match(/^\/(lesson-?\d+)\//i);
    if (!match) continue;
    const id = match[1].toLowerCase();
    if (!byLesson.has(id)) byLesson.set(id, []);
    const list = byLesson.get(id)!;
    if (!list.includes(path)) list.push(path);
  }
  return Array.from(byLesson.entries())
    .map(([id, files]) => ({ id, files: files.sort() }))
    .sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
}

function prettyFallbackTitle(lessonId: string): string {
  const match = lessonId.match(/(\d+)$/);
  return match ? `Урок ${match[1]}` : lessonId;
}

const lessonCache = new Map<string, Promise<LessonContent>>();

/** Drops cached lesson content so the next load picks up admin edits. */
export function invalidateLessonCache(lessonId?: string): void {
  if (lessonId) lessonCache.delete(lessonId);
  else lessonCache.clear();
}

export function listLessonIds(): string[] {
  return discoverLessons().map((l) => l.id);
}

export function loadLesson(lessonId: string): Promise<LessonContent> {
  const cached = lessonCache.get(lessonId);
  if (cached) return cached;
  const promise = buildLesson(lessonId);
  lessonCache.set(lessonId, promise);
  return promise;
}

async function buildLesson(lessonId: string): Promise<LessonContent> {
  const lesson = discoverLessons().find((l) => l.id === lessonId);

  if (!lesson) {
    return {
      id: lessonId,
      title: prettyFallbackTitle(lessonId),
      vocabulary: [],
      material: [],
      phrases: [],
      assets: { images: [] },
      extraTextFiles: [],
      missing: [`Папка ${lessonId} не найдена в проекте.`],
      materialText: "",
      authoredQuestions: [],
      hasContentOverrides: false,
    };
  }

  const missing: string[] = [];
  let vocabularyRaw: string | undefined;
  let materialRaw: string | undefined;
  let video: LessonAsset | undefined;
  let audio: LessonAsset | undefined;
  const images: LessonAsset[] = [];
  const extraTextFiles: { name: string; content: string }[] = [];

  for (const path of lesson.files) {
    const ext = extOf(path);
    const name = baseName(path);

    if (VIDEO_EXT.has(ext)) {
      video = { url: await urlLoaders[path](), name };
      continue;
    }
    if (AUDIO_EXT.has(ext)) {
      audio = { url: await urlLoaders[path](), name };
      continue;
    }
    if (IMAGE_EXT.has(ext)) {
      images.push({ url: await urlLoaders[path](), name });
      continue;
    }

    if (ext === "" || ext === "txt" || ext === "md" || ext === "json") {
      const lowerPath = path.toLowerCase();
      const isVocab = matchesHint(name, VOCAB_HINTS) || lowerPath.includes("/vocabulary/");
      const isMaterial = matchesHint(name, MATERIAL_HINTS) || lowerPath.includes("/material/");

      if (isVocab && !vocabularyRaw) {
        vocabularyRaw = await rawLoaders[path]();
        continue;
      }
      if (isMaterial && !materialRaw) {
        materialRaw = await rawLoaders[path]();
        continue;
      }

      const content = await rawLoaders[path]();
      extraTextFiles.push({ name, content });
    }
  }

  if (!vocabularyRaw) missing.push("Список слов (файл вроде «словарь» или «vocabulary») не найден в папке урока.");
  if (!materialRaw) missing.push("Основной текст урока (файл вроде «урок1» или «lesson») не найден в папке урока.");
  if (!video) missing.push("Видеофайл урока (.mp4/.webm) не найден в папке урока.");
  if (!audio) missing.push("Аудиофайл для аудиопересказа (.mp3/.m4a) не найден в папке урока.");

  // Admin edits, when they exist, stand in for the corresponding file. The
  // text still goes through the same parser, so everything downstream —
  // stages, exercises, the final report — behaves identically.
  const overrides = await fetchContentOverrides(lessonId);

  const materialText = overrides.materialText ?? materialRaw ?? "";
  const vocabulary =
    overrides.vocabulary.length > 0
      ? overrides.vocabulary.map((item, index) => ({
          id: `${lessonId}-vocab-${index}`,
          german: item.german,
          translation: item.translation,
          pronunciation: item.pronunciation ?? undefined,
        }))
      : vocabularyRaw
        ? parseVocabulary(vocabularyRaw, lessonId)
        : [];

  const { blocks, phrases } = materialText ? parseLessonText(materialText) : { blocks: [], phrases: [] };

  const titleBlock = blocks.find((b) => b.type === "title");
  const title = titleBlock && titleBlock.type === "title" ? titleBlock.text : prettyFallbackTitle(lessonId);

  return {
    id: lessonId,
    title,
    vocabulary,
    material: blocks,
    phrases,
    assets: { video, audio, images },
    extraTextFiles,
    missing,
    materialText,
    authoredQuestions: overrides.questions,
    hasContentOverrides: overrides.hasOverrides,
  };
}
