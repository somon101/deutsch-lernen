import { LessonProgress } from "./types";

const STORAGE_KEY = "deutsch-lernen:progress:v1";

type Store = Record<string, LessonProgress>;

export function readStore(): Store {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as Store) : {};
  } catch {
    return {};
  }
}

export function writeStore(store: Store): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(store));
  } catch {
    // localStorage unavailable (private mode / quota) — progress just won't persist.
  }
}
