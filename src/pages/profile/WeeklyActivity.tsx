import { WeeklyActivityDay } from "./types";

export default function WeeklyActivity({ days, avgMinutesPerDay }: { days: WeeklyActivityDay[]; avgMinutesPerDay: number | null }) {
  return (
    <section className="profile-card">
      <div className="profile-section-head">
        <h2 className="profile-section-head__title">Активность за неделю</h2>
      </div>

      <div className="profile-week-row">
        <div className="profile-week-days">
          {days.map((day) => (
            <div className="profile-week-day" key={day.label}>
              <span className={`profile-week-day__dot ${day.active ? "is-active" : ""}`}>{day.active ? "✓" : ""}</span>
              <span className="profile-week-day__label">{day.label}</span>
            </div>
          ))}
        </div>

        <div className="profile-week-avg">
          <span className="profile-week-avg__value">
            {avgMinutesPerDay === null ? "—" : `${(avgMinutesPerDay / 60).toFixed(1)} ч/день`}
          </span>
          <span className="profile-week-avg__label">Средняя активность</span>
        </div>
      </div>
    </section>
  );
}
