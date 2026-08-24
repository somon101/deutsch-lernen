import { useEffect, useState } from "react";
import { MaterialLibraryEntry, builderApi } from "../../admin/builderApi";

/**
 * "Reuse a lesson's material as a starting point instead of writing from
 * scratch" — searches material text across every builder-course lesson (see
 * server/src/courses.ts's searchMaterialLibrary for why legacy lessons
 * aren't included). Picking a result hands the raw text to the caller,
 * which decides how to apply it (e.g. confirm before overwriting non-empty
 * text) — this component only searches and offers what it found.
 */
export default function MaterialLibraryPicker({ onPick }: { onPick: (materialText: string) => void }) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<MaterialLibraryEntry[]>([]);

  useEffect(() => {
    const q = query.trim();
    if (q.length < 2) {
      setResults([]);
      return;
    }
    const timer = setTimeout(() => {
      builderApi.searchMaterials(q).then(setResults).catch(() => {});
    }, 300);
    return () => clearTimeout(timer);
  }, [query]);

  return (
    <div className="builder-material-library">
      <label className="auth-field">
        <span>Найти материал в других уроках (только курсы конструктора)</span>
        <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Например: приветствия" />
      </label>
      {results.length > 0 && (
        <div className="builder-material-library__results">
          {results.map((entry, i) => (
            <button
              type="button"
              key={i}
              className="builder-material-library__item"
              onClick={() => {
                onPick(entry.materialText);
                setQuery("");
                setResults([]);
              }}
            >
              <span className="builder-material-library__label">{entry.label}</span>
              <span className="builder-material-library__snippet">{entry.snippet}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
