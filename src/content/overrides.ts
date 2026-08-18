import { api } from "../auth/api";
import { getAuthToken } from "../auth/tokenStore";
import { AuthoredQuestion } from "./types";

export interface ContentOverrides {
  materialText: string | null;
  vocabulary: { german: string; translation: string; pronunciation: string | null }[];
  questions: AuthoredQuestion[];
  hasOverrides: boolean;
}

const EMPTY: ContentOverrides = {
  materialText: null,
  vocabulary: [],
  questions: [],
  hasOverrides: false,
};

/**
 * Admin-saved edits for a lesson. Returns "nothing" whenever the user isn't
 * signed in or the server can't be reached, so the file-based content keeps
 * working exactly as it did before this feature existed.
 */
export async function fetchContentOverrides(lessonId: string): Promise<ContentOverrides> {
  if (!getAuthToken()) return EMPTY;
  try {
    const data = await api.get<{ content: ContentOverrides }>(`/api/content/${encodeURIComponent(lessonId)}`);
    return data.content ?? EMPTY;
  } catch {
    return EMPTY;
  }
}
