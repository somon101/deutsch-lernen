import { api } from "../auth/api";
import { BuilderCourse, BuilderCourseSummary, BuilderLesson } from "../admin/builderApi";

export type { BuilderCourse, BuilderCourseSummary };
export type BuilderCourseLesson = BuilderLesson;

const base = "/api/courses";

// Small per-course cache, same idea as content/loader.ts's lessonCache — a
// course is fetched once per visit and its lessons reused as the learner
// moves between stages.
const cache = new Map<string, Promise<BuilderCourse>>();

export function invalidateBuilderCourseCache(courseId?: string): void {
  if (courseId) cache.delete(courseId);
  else cache.clear();
}

/** Published builder courses only — a draft never reaches a learner. */
export function listPublishedCourses(): Promise<BuilderCourseSummary[]> {
  return api.get<{ courses: BuilderCourseSummary[] }>(base).then((d) => d.courses);
}

export function loadBuilderCourse(courseId: string): Promise<BuilderCourse> {
  const cached = cache.get(courseId);
  if (cached) return cached;
  const promise = api.get<{ course: BuilderCourse }>(`${base}/${encodeURIComponent(courseId)}`).then((d) => d.course);
  cache.set(courseId, promise);
  return promise;
}
