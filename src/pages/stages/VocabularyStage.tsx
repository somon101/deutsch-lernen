import { useEffect, useState } from "react";
import { LessonContent } from "../../content/types";
import { useLessonProgress, useProgressStore } from "../../progress/ProgressContext";
import WordAudioButton from "../../components/WordAudioButton";
import { playWord, preloadWordAudio } from "../../lib/speech";

export default function VocabularyStage({
  content,
  lessonId,
  onComplete,
}: {
  content: LessonContent;
  lessonId: string;
  onComplete: () => void;
}) {
  const progress = useLessonProgress(lessonId);
  const { setVocabIndex } = useProgressStore();
  const words = content.newVocabulary;
  useEffect(() => {
    preloadWordAudio(words.map((v) => v.audioUrl));
  }, [words]);

  const [index, setIndex] = useState(() => Math.min(progress.vocabIndex, Math.max(words.length - 1, 0)));

  if (content.vocabulary.length === 0) {
    return (
      <div className="stage-panel">
        <div className="stage-eyebrow">Слова урока</div>
        <h1 className="stage-title">Список слов не найден</h1>
        <div className="empty-state">
          <h3>Не хватает материала</h3>
          <p>
            Добавьте файл со словарём урока (например, «словарь» или «vocabulary») в папку {lessonId}, чтобы этот
            этап заработал.
          </p>
        </div>
        <div className="stage-footer">
          <button className="btn btn-primary" onClick={onComplete}>
            Пропустить и продолжить
          </button>
        </div>
      </div>
    );
  }

  if (words.length === 0) {
    return (
      <div className="stage-panel">
        <div className="stage-eyebrow">Слова урока</div>
        <h1 className="stage-title">Новых слов здесь нет</h1>
        <div className="empty-state">
          <h3>Все слова этого урока вы уже изучали раньше</h3>
          <p>Они снова встретятся в материале и заданиях, но заново учить их не нужно — переходите дальше.</p>
        </div>
        <div className="stage-footer">
          <button className="btn btn-primary" onClick={onComplete}>
            Перейти к материалу
          </button>
        </div>
      </div>
    );
  }

  const word = words[index];
  const isLast = index === words.length - 1;

  const goNext = () => {
    if (isLast) {
      onComplete();
      return;
    }
    const next = index + 1;
    setIndex(next);
    setVocabIndex(lessonId, next);
  };

  const goPrev = () => {
    if (index === 0) return;
    const prev = index - 1;
    setIndex(prev);
    setVocabIndex(lessonId, prev);
  };

  return (
    <div className="stage-panel">
      <div className="stage-eyebrow">Слова урока</div>
      <h1 className="stage-title">Изучите слова перед началом урока</h1>
      <p className="stage-subtitle">
        Слово {index + 1} из {words.length}. Просмотрите каждое слово и нажмите «Далее».
      </p>

      <div className="vocab-progress-track">
        {words.map((_, i) => (
          <span key={i} className={`vocab-progress-dot ${i <= index ? "seen" : ""}`} />
        ))}
      </div>

      <div className="vocab-card">
        <span className="vocab-card__counter">
          {index + 1} / {words.length}
        </span>
        <div className="vocab-card__german">
          <button
            type="button"
            className="vocab-card__german-button"
            onClick={() => playWord(word.german, word.audioUrl)}
            title="Прослушать произношение"
          >
            {word.german}
          </button>
          <WordAudioButton word={word.german} audioUrl={word.audioUrl} />
        </div>
        {word.pronunciation && <div className="vocab-card__pron">[{word.pronunciation}]</div>}
        <div className="vocab-card__divider" />
        <div className="vocab-card__translation">{word.translation}</div>
      </div>

      <div className="vocab-nav">
        <button className="btn btn-ghost" onClick={goPrev} disabled={index === 0}>
          ← Назад
        </button>
        <button className="btn btn-primary" onClick={goNext}>
          {isLast ? "Перейти к материалу" : "Далее →"}
        </button>
      </div>
    </div>
  );
}
