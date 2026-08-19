import { Fragment } from "react";
import { Link } from "react-router-dom";

export interface Crumb {
  label: string;
  to?: string;
}

/** Renders "A → B → C", linking every crumb but the last (the current page).
 * Reuses the existing .admin-breadcrumbs styling every admin page already had
 * hand-typed. */
export default function Breadcrumbs({ items }: { items: Crumb[] }) {
  return (
    <p className="admin-breadcrumbs">
      {items.map((item, i) => (
        <Fragment key={i}>
          {i > 0 && " → "}
          {item.to ? <Link to={item.to}>{item.label}</Link> : item.label}
        </Fragment>
      ))}
    </p>
  );
}
