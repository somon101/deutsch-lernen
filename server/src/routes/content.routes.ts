import { Router } from "express";
import { requireAuth } from "../auth/middleware.js";
import { getLessonContent } from "../content.js";

/**
 * Read-only content overrides for learners. Any signed-in user may read the
 * course they are studying; editing lives on the admin router and is checked
 * server-side there.
 */
export const contentRouter = Router();

contentRouter.use(requireAuth);

contentRouter.get("/:lessonId", async (req, res) => {
  res.json({ content: await getLessonContent(req.params.lessonId) });
});
