import { ProfileLevel, ProfileStats } from "./types";

function formatMinutes(minutes: number | null): string {
  if (minutes === null) return "—";
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return `${h}ч ${m}м`;
}

export default function StatsGrid({ stats, level }: { stats: ProfileStats; level: ProfileLevel }) {
  const cards = [
    { icon: "🔥", value: stats.streakDays === null ? "—" : String(stats.streakDays), label: "дней подряд", sub: "Серия" },
    {
      icon: "📈",
      value: stats.overallProgressPercent === null ? "—" : `${stats.overallProgressPercent}%`,
      label: "Общий прогресс",
      sub: null,
    },
    { icon: "⏱️", value: formatMinutes(stats.studyMinutes), label: "Время обучения", sub: null },
    { icon: "⭐", value: level.label ?? "—", label: "Уровень", sub: null },
  ];

  return (
    <div className="profile-stat-grid">
      {cards.map((card) => (
        <div className="profile-stat-card" key={card.label}>
          <span className="profile-stat-card__icon">{card.icon}</span>
          <span className="profile-stat-card__value">{card.value}</span>
          <span className="profile-stat-card__label">{card.sub ?? card.label}</span>
        </div>
      ))}
    </div>
  );
}
