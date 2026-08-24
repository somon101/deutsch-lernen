import { Link, useLocation } from "react-router-dom";

interface NavItem {
  icon: string;
  label: string;
  to?: string;
}

const ITEMS: NavItem[] = [
  { icon: "🏠", label: "Главная", to: "/" },
  { icon: "🎓", label: "Курсы", to: "/courses" },
  { icon: "📖", label: "Словарь" },
  { icon: "📊", label: "Статистика" },
  { icon: "👤", label: "Профиль", to: "/profile" },
];

/** Standalone so it can be mounted on other pages later — only used on the
 * profile page for now, per the current redesign's scope. Items without a
 * `to` don't have a page to link to yet, so they render inert rather than
 * as a dead link. */
export default function BottomNav() {
  const location = useLocation();

  return (
    <nav className="bottom-nav" aria-label="Основная навигация">
      <div className="bottom-nav__inner">
        {ITEMS.map((item) => {
          const active = item.to === location.pathname;
          const className = `bottom-nav__item ${active ? "is-active" : ""}`;
          if (!item.to) {
            return (
              <span className={`${className} bottom-nav__item--inert`} key={item.label}>
                <span className="bottom-nav__icon">{item.icon}</span>
                <span className="bottom-nav__label">{item.label}</span>
              </span>
            );
          }
          return (
            <Link className={className} to={item.to} key={item.label}>
              <span className="bottom-nav__icon">{item.icon}</span>
              <span className="bottom-nav__label">{item.label}</span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
