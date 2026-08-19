import { Router } from "express";
import { requireAuth } from "../auth/middleware.js";
import { getCourse, listCourses } from "../courses.js";

/**
 * Read-only access to builder courses for learners. Any signed-in user may
 * browse and play a published course; editing (and drafts) stay behind the
 * admin-gated builder router. This never touches the legacy file-based
 * course, which keeps living at /api/content and /lesson/:lessonId.
 */
export const learnerCoursesRouter = Router();

learnerCoursesRouter.use(requireAuth);

learnerCoursesRouter.get("/", async (_req, res) => {
  const courses = await listCourses();
  res.json({ courses: courses.filter((c) => c.status === "PUBLISHED") });
});

learnerCoursesRouter.get("/:courseId", async (req, res) => {
  const course = await getCourse(req.params.courseId);
  // A draft course doesn't exist as far as a learner is concerned — even if
  // they guess its id, it 404s exactly like a course that was never made.
  if (!course || course.status !== "PUBLISHED") return res.status(404).json({ error: "Курс не найден" });
  res.json({ course });
});
