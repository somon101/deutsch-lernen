import { API_URL, api } from "../auth/api";
import { getAuthToken } from "../auth/tokenStore";

/** Video/audio override for one of the two legacy (file-based) lessons —
 * same override-if-present mechanism as material/vocabulary, just for media.
 * Null removes the override and falls back to the bundled file again. */
export const legacyMediaApi = {
  upload: async (lessonId: string, kind: "video" | "audio", file: File): Promise<void> => {
    const form = new FormData();
    form.append("kind", kind);
    form.append("file", file);
    const res = await fetch(`${API_URL}/api/admin/content/${encodeURIComponent(lessonId)}/media`, {
      method: "POST",
      headers: { Authorization: `Bearer ${getAuthToken() ?? ""}` },
      body: form,
    });
    const data = await res.json().catch(() => null);
    if (!res.ok) throw new Error(data?.error ?? "Не удалось загрузить файл");
  },
  remove: (lessonId: string, kind: "video" | "audio") =>
    api.delete(`/api/admin/content/${encodeURIComponent(lessonId)}/media?kind=${kind}`),
};

/** LessonFlowCanvas layout for one of the two legacy lessons — admin-only,
 * never surfaced to learners (unlike material/vocabulary, it has no
 * override-if-present fallback: it's purely the editor's own node
 * positions/edges, read straight from LessonContent.canvasLayout). */
export const legacyLayoutApi = {
  get: (lessonId: string) =>
    api.get<{ content: { canvasLayout: unknown } }>(`/api/admin/content/${encodeURIComponent(lessonId)}`).then((d) => d.content.canvasLayout),
  save: (lessonId: string, layout: unknown) =>
    api.put(`/api/admin/content/${encodeURIComponent(lessonId)}/layout`, { layout }),
};
