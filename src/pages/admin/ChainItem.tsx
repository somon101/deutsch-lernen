import { ReactNode } from "react";

/** One expandable element of a lesson chain — shared by the course builder's
 * lesson editor and the legacy lesson editor, since both walk the same
 * fixed 8-step structure. */
export default function ChainItem({
  index,
  label,
  note,
  summary,
  editable,
  open,
  onToggle,
  children,
}: {
  index: number;
  label: string;
  note?: string;
  summary: string;
  editable: boolean;
  open: boolean;
  onToggle: () => void;
  children?: ReactNode;
}) {
  return (
    <div className={`chain-item ${open ? "is-open" : ""} ${editable ? "" : "is-readonly"}`}>
      <button type="button" className="chain-item__head" onClick={onToggle} disabled={!editable}>
        <span className="chain-item__index">{index}</span>
        <span className="chain-item__label">
          {label}
          {note && <span className="chain-item__note">{note}</span>}
        </span>
        <span className="chain-item__summary">{summary}</span>
        {editable && <span className="chain-item__caret">{open ? "▾" : "▸"}</span>}
      </button>
      {open && editable && <div className="chain-item__body">{children}</div>}
    </div>
  );
}
