import { Route, Routes } from "react-router-dom";
import Home from "./pages/Home";
import LessonRedirect from "./pages/LessonRedirect";
import LessonPage from "./pages/LessonPage";

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<Home />} />
      <Route path="/lesson/:lessonId" element={<LessonRedirect />} />
      <Route path="/lesson/:lessonId/:stage" element={<LessonPage />} />
    </Routes>
  );
}
