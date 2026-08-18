import { useState } from "react";
import { LessonBlock, LessonContent, VocabularyEntry } from "../../content/types";
import WordAudioButton from "../../components/WordAudioButton";

interface Group {
  title?: string;
  blocks: LessonBlock[];
}

function groupBlocks(blocks: LessonBlock[]): Group[] {
  const groups: Group[] = [];
  let current: Group = { blocks: [] };

  for (const block of blocks) {
    if (block.type === "step") {
      if (current.blocks.length > 0) groups.push(current);
      current = { title: `Шаг ${block.number}. ${block.title}`, blocks: [block] };
    } else {
      current.blocks.push(block);
    }
  }
  if (current.blocks.length > 0) groups.push(current);
  return groups;
}

export default function MaterialStage({
  content,
  onComplete,
}: {
  content: LessonContent;
  onComplete: () => void;
}) {
  const groups = groupBlocks(content.material);
  const [page, setPage] = useState(0);

  if (groups.length === 0) {
    return (
      <div className="stage-panel">
        <div className="stage-eyebrow">Материал урока</div>
        <h1 className="stage-title">Текст урока не найден</h1>
        <div className="empty-state">
          <h3>Не хватает материала</h3>
          <p>Добавьте текстовый файл с материалом урока (например, «урок1» или «lesson») в папку урока.</p>
        </div>
        <div className="stage-footer">
          <button className="btn btn-primary" onClick={onComplete}>
            Пропустить и продолжить
          </button>
        </div>
      </div>
    );
  }

  const isLast = page === groups.length - 1;
  const group = groups[page];

  const goNext = () => {
    if (isLast) {
      onComplete();
      return;
    }
    setPage((p) => p + 1);
  };
  const goPrev = () => setPage((p) => Math.max(0, p - 1));

  return (
    <div className="stage-panel">
      <div className="stage-eyebrow">Материал урока</div>
      <h1 className="stage-title">{content.title}</h1>
      <p className="material-progress">
        Раздел {page + 1} из {groups.length}
      </p>

      <div className="material-card">
        {group.blocks.map((block, i) => (
          <MaterialBlockView key={i} block={block} vocabulary={content.vocabulary} />
        ))}
      </div>

      <div className="vocab-nav">
        <button className="btn btn-ghost" onClick={goPrev} disabled={page === 0}>
          ← Назад
        </button>
        <button className="btn btn-primary" onClick={goNext}>
          {isLast ? "Перейти к видео" : "Далее →"}
        </button>
      </div>
    </div>
  );
}

function MaterialBlockView({ block, vocabulary }: { block: LessonBlock; vocabulary: VocabularyEntry[] }) {
  switch (block.type) {
    case "title":
      return <h2 className="material-block--title">{block.text}</h2>;
    case "step":
      return (
        <div className="material-block--step-title">
          <span className="material-block--step-badge">{block.number}</span>
          {block.title}
        </div>
      );
    case "subheading":
      return (
        <div className="material-block--subheading">
          {block.icon && <span>{block.icon}</span>}
          <span>{block.text}</span>
        </div>
      );
    case "phrase": {
      // Reuse the word's recorded pronunciation when the vocabulary has one.
      const recorded = vocabulary.find(
        (v) => v.german.toLowerCase() === block.german.toLowerCase(),
      )?.audioUrl;
      return (
        <div className="material-block--phrase">
          <span className="material-block--phrase-de">
            {block.icon ? `${block.icon} ` : ""}
            {block.german}
            {block.pronunciation && <span className="material-block--phrase-pron">[{block.pronunciation}]</span>}
            <WordAudioButton word={block.german} audioUrl={recorded} size="sm" />
          </span>
          <span className="material-block--phrase-ru">{block.translation}</span>
        </div>
      );
    }
    case "line":
      return <p className={`material-block--line ${block.tight ? "tight" : ""}`}>{block.text}</p>;
  }
}
