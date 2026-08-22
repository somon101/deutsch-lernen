import { Navigate, Route, Routes } from "react-router-dom";
import Home from "./pages/Home";
import LessonRedirect from "./pages/LessonRedirect";
import LessonPage from "./pages/LessonPage";
import LoginPage from "./pages/LoginPage";
import ProfilePage from "./pages/ProfilePage";
import CoursesPage from "./pages/CoursesPage";
import CourseLessonsPage from "./pages/CourseLessonsPage";
import BuilderLessonPage from "./pages/BuilderLessonPage";
import AdminUsersPage from "./pages/admin/AdminUsersPage";
import AdminUserDetailPage from "./pages/admin/AdminUserDetailPage";
import AdminCoursesHubPage from "./pages/admin/AdminCoursesHubPage";
import AdminLegacyLessonsPage from "./pages/admin/AdminLegacyLessonsPage";
import AdminLessonEditPage from "./pages/admin/AdminLessonEditPage";
import BuilderCourseEditPage from "./pages/admin/BuilderCourseEditPage";
import ForbiddenPage from "./pages/ForbiddenPage";
import ProtectedRoute from "./components/ProtectedRoute";

export default function App() {
  return (
    <Routes>
      <Route
        path="/"
        element={
          <ProtectedRoute>
            <Home />
          </ProtectedRoute>
        }
      />
      <Route
        path="/lesson/:lessonId"
        element={
          <ProtectedRoute>
            <LessonRedirect />
          </ProtectedRoute>
        }
      />
      <Route
        path="/lesson/:lessonId/:stage"
        element={
          <ProtectedRoute>
            <LessonPage />
          </ProtectedRoute>
        }
      />

      <Route
        path="/courses"
        element={
          <ProtectedRoute>
            <CoursesPage />
          </ProtectedRoute>
        }
      />
      <Route
        path="/courses/:courseId"
        element={
          <ProtectedRoute>
            <CourseLessonsPage />
          </ProtectedRoute>
        }
      />
      <Route
        path="/courses/:courseId/lesson/:lessonId/:stage"
        element={
          <ProtectedRoute>
            <BuilderLessonPage />
          </ProtectedRoute>
        }
      />

      <Route path="/login" element={<LoginPage />} />
      <Route
        path="/profile"
        element={
          <ProtectedRoute>
            <ProfilePage />
          </ProtectedRoute>
        }
      />
      <Route
        path="/admin"
        element={
          <ProtectedRoute adminOnly>
            <AdminUsersPage />
          </ProtectedRoute>
        }
      />
      <Route
        path="/admin/courses"
        element={
          <ProtectedRoute staffOnly>
            <AdminCoursesHubPage />
          </ProtectedRoute>
        }
      />
      <Route
        path="/admin/courses/legacy"
        element={
          <ProtectedRoute staffOnly>
            <AdminLegacyLessonsPage />
          </ProtectedRoute>
        }
      />
      <Route
        path="/admin/lessons/:lessonId"
        element={
          <ProtectedRoute staffOnly>
            <AdminLessonEditPage />
          </ProtectedRoute>
        }
      />
      {/* Old constructor list URL — kept as a redirect so existing bookmarks/links still work. */}
      <Route path="/admin/builder" element={<Navigate to="/admin/courses" replace />} />
      <Route
        path="/admin/builder/:courseId"
        element={
          <ProtectedRoute staffOnly>
            <BuilderCourseEditPage />
          </ProtectedRoute>
        }
      />
      <Route
        path="/admin/users/:id"
        element={
          <ProtectedRoute adminOnly>
            <AdminUserDetailPage />
          </ProtectedRoute>
        }
      />
      <Route path="/403" element={<ForbiddenPage />} />
    </Routes>
  );
}
