import { Link } from "react-router-dom";

interface NavRow {
  icon: string;
  label: string;
  /** Link target for a real destination; omit for a not-yet-built section
   * (rendered inert with a "скоро" tag instead of a dead click). */
  to?: string;
  /** In-page anchor for a section further down this same page. */
  anchor?: string;
}

const ROWS: NavRow[] = [
  { icon: "📚", label: "Мои курсы", to: "/courses" },
  { icon: "📖", label: "Словарь" },
  { icon: "⭐", label: "Избранное" },
  { icon: "🕘", label: "История занятий", anchor: "#history" },
  { icon: "⚙️", label: "Настройки", anchor: "#settings" },
];

export default function ProfileNavList() {
  return (
    <section className="profile-card profile-nav-list">
      {ROWS.map((row) => {
        const content = (
          <>
            <span className="profile-nav-row__icon">{row.icon}</span>
            <span className="profile-nav-row__label">{row.label}</span>
            {row.to || row.anchor ? (
              <span className="profile-nav-row__chevron">›</span>
            ) : (
              <span className="profile-nav-row__soon">скоро</span>
            )}
          </>
        );

        if (row.to) {
          return (
            <Link className="profile-nav-row" to={row.to} key={row.label}>
              {content}
            </Link>
          );
        }
        if (row.anchor) {
          return (
            <a className="profile-nav-row" href={row.anchor} key={row.label}>
              {content}
            </a>
          );
        }
        return (
          <div className="profile-nav-row profile-nav-row--inert" key={row.label}>
            {content}
          </div>
        );
      })}
    </section>
  );
}
