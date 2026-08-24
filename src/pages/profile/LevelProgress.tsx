import { ProfileLevel } from "./types";

export default function LevelProgress({ level }: { level: ProfileLevel }) {
  const hasLevel = level.label !== null && level.progressPercent !== null;

  return (
    <section className="profile-card profile-level-card">
      <div className="profile-level-card__row">
        <div>
          <p className="profile-level-card__eyebrow">Ваш уровень</p>
          <h2 className="profile-level-card__title">{level.label ?? "Пока не определён"}</h2>
        </div>
        <span className="profile-level-card__badge" aria-hidden="true">
          ⭐
        </span>
      </div>

      <div className="profile-progress-bar">
        <div className="profile-progress-bar__fill" style={{ width: `${level.progressPercent ?? 0}%` }} />
      </div>

      <p className="profile-level-card__hint">
        {hasLevel
          ? `${level.progressPercent}% до следующего уровня`
          : "Уровень появится здесь автоматически, когда наберётся достаточно данных о пройденных уроках."}
      </p>
    </section>
  );
}
