import { Route, Routes } from "react-router-dom";
import Home from "./pages/Home";
import LessonRedirect from "./pages/LessonRedirect";
import LessonPage from "./pages/LessonPage";
import LoginPage from "./pages/LoginPage";
import ProfilePage from "./pages/ProfilePage";
import AdminUsersPage from "./pages/admin/AdminUsersPage";
import AdminUserDetailPage from "./pages/admin/AdminUserDetailPage";
import AdminCoursesPage from "./pages/admin/AdminCoursesPage";
import AdminLessonEditPage from "./pages/admin/AdminLessonEditPage";
import BuilderCoursesPage from "./pages/admin/BuilderCoursesPage";
import BuilderCourseEditPage from "./pages/admin/BuilderCourseEditPage";
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
          <ProtectedRoute adminOnly>
            <AdminCoursesPage />
          </ProtectedRoute>
        }
      />
      <Route
        path="/admin/lessons/:lessonId"
        element={
          <ProtectedRoute adminOnly>
            <AdminLessonEditPage />
          </ProtectedRoute>
        }
      />
      <Route
        path="/admin/builder"
        element={
          <ProtectedRoute adminOnly>
            <BuilderCoursesPage />
          </ProtectedRoute>
        }
      />
      <Route
        path="/admin/builder/:courseId"
        element={
          <ProtectedRoute adminOnly>
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
    </Routes>
  );
}
