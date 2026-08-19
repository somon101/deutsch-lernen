import { Link } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import { assetUrl } from "../auth/api";

/** Top-nav link to the current user's profile, with their avatar photo (or
 * initials, if they haven't uploaded one) shown next to the label. Used
 * everywhere the nav currently links to "/profile", so the same photo shows
 * up consistently across learner and admin pages. */
export default function ProfileNavLink({ label }: { label?: string }) {
  const { user } = useAuth();
  if (!user) return null;

  return (
    <Link to="/profile" className="btn btn-ghost nav-profile-link">
      <span>{label ?? user.firstName}</span>
      {user.avatarUrl ? (
        <img className="nav-profile-avatar" src={assetUrl(user.avatarUrl)} alt="" />
      ) : (
        <span className="nav-profile-avatar nav-profile-avatar--placeholder">
          {user.firstName[0]}
          {user.lastName[0]}
        </span>
      )}
    </Link>
  );
}
