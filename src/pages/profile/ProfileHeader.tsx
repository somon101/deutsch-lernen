import { ChangeEvent, RefObject } from "react";
import { assetUrl } from "../../auth/api";
import { StoredAuthUser } from "../../auth/tokenStore";
import { ProfileStats } from "./types";

/** "—" reads as "not tracked yet" rather than a fabricated number — see
 * types.ts for why these fields are still null. */
function formatCount(n: number | null): string {
  return n === null ? "—" : String(n);
}

export default function ProfileHeader({
  user,
  bio,
  stats,
  avatarBusy,
  fileInputRef,
  onAvatarChange,
  onAvatarDelete,
}: {
  user: StoredAuthUser;
  /** No bio field exists on the account yet — pass a value only for a demo
   * review; omit it (or leave undefined) once this is wired to a real one. */
  bio?: string;
  stats: ProfileStats;
  avatarBusy: boolean;
  fileInputRef: RefObject<HTMLInputElement>;
  onAvatarChange: (e: ChangeEvent<HTMLInputElement>) => void;
  onAvatarDelete: () => void;
}) {
  return (
    <section className="profile-card profile-hero">
      <div className="profile-hero__top">
        {user.avatarUrl ? (
          <img className="profile-avatar profile-avatar--lg" src={assetUrl(user.avatarUrl)} alt="" />
        ) : (
          <div className="profile-avatar profile-avatar--lg profile-avatar--placeholder">
            {user.firstName[0]}
            {user.lastName[0]}
          </div>
        )}

        <div className="profile-hero__identity">
          <h1 className="profile-hero__name">
            {user.firstName} {user.lastName}
          </h1>
          <p className="profile-hero__username">@{user.username}</p>
          {bio && <p className="profile-hero__bio">{bio}</p>}
        </div>

        <div className="profile-avatar-actions">
          <button type="button" className="btn btn-secondary" disabled={avatarBusy} onClick={() => fileInputRef.current?.click()}>
            {user.avatarUrl ? "Заменить фото" : "Загрузить фото"}
          </button>
          {user.avatarUrl && (
            <button type="button" className="btn btn-ghost" disabled={avatarBusy} onClick={onAvatarDelete}>
              Удалить
            </button>
          )}
          <input ref={fileInputRef} type="file" accept="image/jpeg,image/png,image/webp" hidden onChange={onAvatarChange} />
        </div>
      </div>

      <div className="profile-social-row">
        <div className="profile-social-stat">
          <span className="profile-social-stat__value">{formatCount(stats.followers)}</span>
          <span className="profile-social-stat__label">Подписчики</span>
        </div>
        <div className="profile-social-stat">
          <span className="profile-social-stat__value">{formatCount(stats.mutualFollowers)}</span>
          <span className="profile-social-stat__label">Взаимные</span>
        </div>
        <div className="profile-social-stat">
          <span className="profile-social-stat__value">{formatCount(stats.following)}</span>
          <span className="profile-social-stat__label">Подписки</span>
        </div>
      </div>
    </section>
  );
}
