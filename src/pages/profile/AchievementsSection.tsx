import { Achievement } from "./types";

/**
 * Structure is ready for a future achievements system, but nothing
 * auto-populates it yet — no fabricated badges. An empty `achievements`
 * array renders the empty state below rather than placeholder medals.
 */
export default function AchievementsSection({ achievements }: { achievements: Achievement[] }) {
  return (
    <section className="profile-card">
      <div className="profile-section-head">
        <h2 className="profile-section-head__title">Достижения</h2>
      </div>

      {achievements.length === 0 ? (
        <div className="profile-achievements-empty">
          <span className="profile-achievements-empty__icon" aria-hidden="true">
            🏅
          </span>
          <p>Пока нет достижений</p>
          <p className="profile-achievements-empty__hint">Они появятся здесь автоматически по мере прохождения уроков.</p>
        </div>
      ) : (
        <div className="profile-achievements-grid">
          {achievements.map((a) => (
            <div className={`profile-achievement profile-achievement--${a.status}`} key={a.id}>
              <span className="profile-achievement__icon">
                {a.status === "locked" ? "🔒" : a.icon}
              </span>
              <span className="profile-achievement__title">{a.title}</span>
              <span className="profile-achievement__subtitle">{a.subtitle}</span>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}
