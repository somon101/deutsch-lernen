import { api, API_URL } from "../auth/api";
import { getAuthToken } from "../auth/tokenStore";

export type CourseStatus = "DRAFT" | "PUBLISHED";
export type QuestionSet = "minitest" | "practice" | "review";

export interface BuilderWord {
  german: string;
  translation: string;
  pronunciation: string | null;
  audioUrl: string | null;
}

export interface BuilderQuestion {
  setName: QuestionSet;
  prompt: string;
  options: string[];
  correctAnswer: string;
}

export interface BuilderLesson {
  id: string;
  title: string;
  description: string;
  materialText: string;
  videoUrl: string | null;
  audioUrl: string | null;
  position: number;
  vocabulary: BuilderWord[];
  questions: BuilderQuestion[];
}

export interface BuilderCourse {
  id: string;
  title: string;
  description: string;
  coverUrl: string | null;
  status: CourseStatus;
  position: number;
  updatedAt: string;
  lessons: BuilderLesson[];
}

export interface BuilderCourseSummary {
  id: string;
  title: string;
  description: string;
  coverUrl: string | null;
  status: CourseStatus;
  position: number;
  lessonCount: number;
  wordCount: number;
  questionCount: number;
  updatedAt: string;
}

const base = "/api/builder/courses";

export const builderApi = {
  list: () => api.get<{ courses: BuilderCourseSummary[] }>(base).then((d) => d.courses),
  get: (courseId: string) => api.get<{ course: BuilderCourse }>(`${base}/${courseId}`).then((d) => d.course),
  create: (input: { title: string; description?: string }) =>
    api.post<{ course: BuilderCourse }>(base, input).then((d) => d.course),
  update: (courseId: string, input: { title?: string; description?: string; status?: CourseStatus }) =>
    api.patch<{ course: BuilderCourse }>(`${base}/${courseId}`, input).then((d) => d.course),
  remove: (courseId: string) => api.delete<{ ok: boolean }>(`${base}/${courseId}`),
  reorderCourses: (ids: string[]) =>
    api.post<{ courses: BuilderCourseSummary[] }>(`${base}/reorder`, { ids }).then((d) => d.courses),

  addLesson: (courseId: string, input: { title: string; description?: string }) =>
    api.post<{ course: BuilderCourse }>(`${base}/${courseId}/lessons`, input).then((d) => d.course),
  updateLesson: (
    courseId: string,
    lessonId: string,
    input: { title?: string; description?: string; materialText?: string },
  ) => api.patch<{ course: BuilderCourse }>(`${base}/${courseId}/lessons/${lessonId}`, input).then((d) => d.course),
  removeLesson: (courseId: string, lessonId: string) =>
    api.delete<{ course: BuilderCourse }>(`${base}/${courseId}/lessons/${lessonId}`).then((d) => d.course),
  reorderLessons: (courseId: string, ids: string[]) =>
    api.post<{ course: BuilderCourse }>(`${base}/${courseId}/lessons/reorder`, { ids }).then((d) => d.course),

  saveVocabulary: (courseId: string, lessonId: string, vocabulary: Omit<BuilderWord, "audioUrl">[] | BuilderWord[]) =>
    api
      .put<{ course: BuilderCourse }>(`${base}/${courseId}/lessons/${lessonId}/vocabulary`, { vocabulary })
      .then((d) => d.course),
  saveQuestions: (courseId: string, lessonId: string, questions: BuilderQuestion[]) =>
    api
      .put<{ course: BuilderCourse }>(`${base}/${courseId}/lessons/${lessonId}/questions`, { questions })
      .then((d) => d.course),

  removeMedia: (courseId: string, lessonId: string, kind: "video" | "audio") =>
    api
      .delete<{ course: BuilderCourse }>(`${base}/${courseId}/lessons/${lessonId}/media?kind=${kind}`)
      .then((d) => d.course),
  removeCover: (courseId: string) =>
    api.delete<{ course: BuilderCourse }>(`${base}/${courseId}/cover`).then((d) => d.course),
};

/** Multipart uploads go through fetch directly — the shared helper is JSON-only. */
async function upload(path: string, form: FormData): Promise<BuilderCourse> {
  const res = await fetch(`${API_URL}${path}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${getAuthToken() ?? ""}` },
    body: form,
  });
  const data = await res.json().catch(() => null);
  if (!res.ok) throw new Error(data?.error ?? "Не удалось загрузить файл");
  return data.course as BuilderCourse;
}

export function uploadLessonMedia(
  courseId: string,
  lessonId: string,
  kind: "video" | "audio",
  file: File,
): Promise<BuilderCourse> {
  const form = new FormData();
  form.append("kind", kind);
  form.append("file", file);
  return upload(`${base}/${courseId}/lessons/${lessonId}/media`, form);
}

export function uploadCourseCover(courseId: string, file: File): Promise<BuilderCourse> {
  const form = new FormData();
  form.append("file", file);
  return upload(`${base}/${courseId}/cover`, form);
}
