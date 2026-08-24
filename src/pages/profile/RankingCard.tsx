import { ProfileRanking } from "./types";

export default function RankingCard({ ranking }: { ranking: ProfileRanking }) {
  return (
    <section className="profile-card profile-ranking">
      <span className="profile-ranking__icon" aria-hidden="true">
        🏆
      </span>
      <div className="profile-ranking__body">
        <p className="profile-ranking__eyebrow">Ваш рейтинг</p>
        <p className="profile-ranking__rank">{ranking.rank === null ? "—" : `#${ranking.rank}`}</p>
      </div>
      <div className="profile-ranking__col">
        <span className="profile-ranking__value">{ranking.percentile === null ? "—" : `Топ ${ranking.percentile}%`}</span>
        <span className="profile-ranking__label">По неделе</span>
      </div>
      <div className="profile-ranking__col">
        <span className="profile-ranking__value">
          {ranking.totalStudents === null ? "—" : `из ${ranking.totalStudents.toLocaleString("ru-RU")}`}
        </span>
        <span className="profile-ranking__label">Среди всех студентов</span>
      </div>
    </section>
  );
}
