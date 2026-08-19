import { BuilderBlock } from "../admin/builderApi";
import { api } from "../auth/api";
import { getAuthToken } from "../auth/tokenStore";
import { AuthoredQuestion } from "./types";

export interface ContentOverrides {
  materialText: string | null;
  videoUrl: string | null;
  audioUrl: string | null;
  vocabulary: { id: string; german: string; translation: string; pronunciation: string | null; audioUrl: string | null }[];
  questions: AuthoredQuestion[];
  blocks: BuilderBlock[];
  hasOverrides: boolean;
}

const EMPTY: ContentOverrides = {
  materialText: null,
  videoUrl: null,
  audioUrl: null,
  vocabulary: [],
  questions: [],
  blocks: [],
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
