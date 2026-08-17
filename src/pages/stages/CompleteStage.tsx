import { useEffect, useMemo, useRef, useState } from "react";
import { Link } from "react-router-dom";
import { LessonContent } from "../../content/types";
import { useLessonProgress, useProgressStore } from "../../progress/ProgressContext";
import { QuizResult } from "../../progress/types";
import { playSound } from "../../lib/sound";
import progressCompleteSoundUrl from "../../../sounds/progress-complete.mp3";

function pct(result?: QuizResult): number | null {
  return result && result.total > 0 ? Math.round((result.correct / result.total) * 100) : null;
}

// Whole report animates in ~5s total (matches progress-complete.mp3's
// length), split evenly across however many stats actually have a value —
// clamped so a single stat doesn't crawl and a long row of stats doesn't rush.
const TOTAL_ANIMATION_MS = 5000;
const MIN_STAT_MS = 900;
const MAX_STAT_MS = 3000;

function useCountUp(value: number, startDelay: number, duration: number): number {
  const [display, setDisplay] = useState(0);

  useEffect(() => {
    let raf = 0;
    let start: number | null = null;

    const timeoutId = window.setTimeout(() => {
      const step = (now: number) => {
        if (start === null) start = now;
        const t = Math.min(1, (now - start) / duration);
        const eased = 1 - Math.pow(1 - t, 3); // ease-out cubic — quick start, gentle settle
        setDisplay(Math.round(eased * value));
        if (t < 1) {
          raf = requestAnimationFrame(step);
        }
      };
      raf = requestAnimationFrame(step);
    }, startDelay);

    return () => {
      window.clearTimeout(timeoutId);
      if (raf) cancelAnimationFrame(raf);
    };
  }, [value, startDelay, duration]);

  return display;
}

function AnimatedNumber({
  value,
  suffix,
  startDelay,
  duration,
}: {
  value: number;
  suffix: string;
  startDelay: number;
  duration: number;
}) {
  const display = useCountUp(value, startDelay, duration);
  return (
    <>
      {display}
      {suffix}
    </>
  );
}

const RING_RADIUS = 42;
const RING_CIRCUMFERENCE = 2 * Math.PI * RING_RADIUS;

function AnimatedRingStat({
  value,
  label,
  startDelay,
  duration,
  color,
}: {
  value: number;
  label: string;
  startDelay: number;
  duration: number;
  color: string;
}) {
  const display = useCountUp(value, startDelay, duration);
  const clamped = Math.max(0, Math.min(100, display));
  const offset = RING_CIRCUMFERENCE * (1 - clamped / 100);

  return (
    <div className="stat-ring-card">
      <div className="stat-ring-wrap">
        <svg viewBox="0 0 100 100" className="stat-ring" aria-hidden="true">
          <circle className="stat-ring-track" cx="50" cy="50" r={RING_RADIUS} />
          <circle
            className="stat-ring-fill"
            cx="50"
            cy="50"
            r={RING_RADIUS}
            style={{ stroke: color, strokeDasharray: RING_CIRCUMFERENCE, strokeDashoffset: offset }}
          />
        </svg>
        <div className="stat-ring-value">{display}%</div>
      </div>
      <span className="stat-ring-label">{label}</span>
    </div>
  );
}

// Small pop-in stagger for each confetti bit so they don't all appear on the
// same frame — starts once the ribbon has mostly drawn itself in.
const DOT_BASE_DELAY = 720;
const DOT_STEP = 45;
const dotDelay = (index: number) => `${DOT_BASE_DELAY + index * DOT_STEP}ms`;

function ConfettiRibbons() {
  return (
    <div className="complete-confetti">
      <svg className="confetti-left" viewBox="0 0 220 560" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
        <path
          className="confetti-ribbon-path"
          pathLength={1}
          d="M -30 60 C 40 40, 60 120, 130 130 C 190 138, 170 220, 120 260 C 60 305, 90 380, 40 430 C 0 465, 20 520, -30 545"
          stroke="#4a5cf0"
          strokeWidth="20"
          strokeLinecap="round"
          opacity="0.85"
        />
        <path
          className="confetti-ribbon-path"
          pathLength={1}
          d="M -30 170 C 30 155, 40 235, 100 255 C 155 273, 130 345, 75 375 C 25 402, 45 465, -10 495"
          stroke="#1fa974"
          strokeWidth="16"
          strokeLinecap="round"
          opacity="0.8"
          style={{ animationDelay: "120ms" }}
        />
        <rect className="confetti-dot" style={{ animationDelay: dotDelay(0) }} x="150" y="55" width="10" height="10" rx="2" fill="#f6b73c" transform="rotate(20 155 60)" />
        <circle className="confetti-dot" style={{ animationDelay: dotDelay(1) }} cx="172" cy="112" r="5" fill="#4a5cf0" />
        <rect className="confetti-dot" style={{ animationDelay: dotDelay(2) }} x="58" y="38" width="8" height="8" rx="2" fill="#1fa974" transform="rotate(45 62 42)" />
        <circle className="confetti-dot" style={{ animationDelay: dotDelay(3) }} cx="28" cy="88" r="4" fill="#f6b73c" />
        <rect className="confetti-dot" style={{ animationDelay: dotDelay(4) }} x="132" y="182" width="9" height="9" rx="2" fill="#8b5cf6" transform="rotate(15 136 186)" />
        <circle className="confetti-dot" style={{ animationDelay: dotDelay(5) }} cx="150" cy="300" r="5" fill="#1fa974" />
        <rect className="confetti-dot" style={{ animationDelay: dotDelay(6) }} x="38" y="258" width="8" height="8" rx="2" fill="#4a5cf0" transform="rotate(30 42 262)" />
        <circle className="confetti-dot" style={{ animationDelay: dotDelay(7) }} cx="92" cy="398" r="4" fill="#f6b73c" />
        <rect className="confetti-dot" style={{ animationDelay: dotDelay(8) }} x="128" y="420" width="9" height="9" rx="2" fill="#1fa974" transform="rotate(60 132 424)" />
        <circle className="confetti-dot" style={{ animationDelay: dotDelay(9) }} cx="58" cy="478" r="5" fill="#8b5cf6" />
        <rect className="confetti-dot" style={{ animationDelay: dotDelay(10) }} x="18" y="378" width="8" height="8" rx="2" fill="#f6b73c" transform="rotate(10 22 382)" />
        <circle className="confetti-dot" style={{ animationDelay: dotDelay(11) }} cx="182" cy="220" r="4" fill="#4a5cf0" />
      </svg>
      <svg className="confetti-right" viewBox="0 0 220 560" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
        <path
          className="confetti-ribbon-path"
          pathLength={1}
          d="M 250 60 C 180 40, 160 120, 90 130 C 30 138, 50 220, 100 260 C 160 305, 130 380, 180 430 C 220 465, 200 520, 250 545"
          stroke="#8b5cf6"
          strokeWidth="20"
          strokeLinecap="round"
          opacity="0.85"
        />
        <path
          className="confetti-ribbon-path"
          pathLength={1}
          d="M 250 170 C 190 155, 180 235, 120 255 C 65 273, 90 345, 145 375 C 195 402, 175 465, 230 495"
          stroke="#f6b73c"
          strokeWidth="16"
          strokeLinecap="round"
          opacity="0.8"
          style={{ animationDelay: "120ms" }}
        />
        <rect className="confetti-dot" style={{ animationDelay: dotDelay(0) }} x="60" y="55" width="10" height="10" rx="2" fill="#4a5cf0" transform="rotate(-20 65 60)" />
        <circle className="confetti-dot" style={{ animationDelay: dotDelay(1) }} cx="48" cy="112" r="5" fill="#8b5cf6" />
        <rect className="confetti-dot" style={{ animationDelay: dotDelay(2) }} x="152" y="38" width="8" height="8" rx="2" fill="#f6b73c" transform="rotate(-45 156 42)" />
        <circle className="confetti-dot" style={{ animationDelay: dotDelay(3) }} cx="192" cy="88" r="4" fill="#1fa974" />
        <rect className="confetti-dot" style={{ animationDelay: dotDelay(4) }} x="79" y="182" width="9" height="9" rx="2" fill="#1fa974" transform="rotate(-15 83 186)" />
        <circle className="confetti-dot" style={{ animationDelay: dotDelay(5) }} cx="70" cy="300" r="5" fill="#f6b73c" />
        <rect className="confetti-dot" style={{ animationDelay: dotDelay(6) }} x="174" y="258" width="8" height="8" rx="2" fill="#8b5cf6" transform="rotate(-30 178 262)" />
        <circle className="confetti-dot" style={{ animationDelay: dotDelay(7) }} cx="128" cy="398" r="4" fill="#4a5cf0" />
        <rect className="confetti-dot" style={{ animationDelay: dotDelay(8) }} x="83" y="420" width="9" height="9" rx="2" fill="#8b5cf6" transform="rotate(-60 87 424)" />
        <circle className="confetti-dot" style={{ animationDelay: dotDelay(9) }} cx="162" cy="478" r="5" fill="#f6b73c" />
        <rect className="confetti-dot" style={{ animationDelay: dotDelay(10) }} x="194" y="378" width="8" height="8" rx="2" fill="#4a5cf0" transform="rotate(-10 198 382)" />
        <circle className="confetti-dot" style={{ animationDelay: dotDelay(11) }} cx="38" cy="220" r="4" fill="#8b5cf6" />
      </svg>
    </div>
  );
}

export default function CompleteStage({
  lessonId,
  content,
}: {
  lessonId: string;
  content: LessonContent;
}) {
  const progress = useLessonProgress(lessonId);
  const { completeLesson } = useProgressStore();

  useEffect(() => {
    if (!progress.completedStages.includes("complete")) {
      completeLesson(lessonId);
    }
  }, [lessonId, progress.completedStages, completeLesson]);

  const soundPlayedRef = useRef(false);

  // Plays exactly once, right as the report mounts — in step with the stats
  // starting their count-up from 0, not when they finish.
  useEffect(() => {
    if (!soundPlayedRef.current) {
      soundPlayedRef.current = true;
      playSound(progressCompleteSoundUrl);
    }
  }, []);

  const miniTestPct = pct(progress.miniTestResult);
  const practicePct = pct(progress.practiceResult);
  const reviewPct = pct(progress.reviewResult);

  // Existing progress math is untouched — only how these numbers get
  // *displayed* changes below.
  const ringStats = useMemo(
    () => [
      { key: "minitest", value: miniTestPct, label: "мини-тест", color: "var(--color-success)" },
      { key: "practice", value: practicePct, label: "практика", color: "var(--color-primary)" },
      { key: "review", value: reviewPct, label: "закрепление", color: "var(--color-primary)" },
    ],
    [miniTestPct, practicePct, reviewPct],
  );

  const animatableCount = 1 /* vocab */ + ringStats.filter((s) => s.value !== null).length;
  const perStatMs =
    animatableCount > 0 ? Math.min(MAX_STAT_MS, Math.max(MIN_STAT_MS, TOTAL_ANIMATION_MS / animatableCount)) : 0;

  let animatedIndex = 0;
  const vocabDelay = animatedIndex * perStatMs;
  animatedIndex += 1;

  return (
    <div className="complete-decorated">
      <ConfettiRibbons />
      <div className="stage-panel">
        <div className="stage-eyebrow">Урок завершён</div>
        <h1 className="stage-title">Отличная работа!</h1>
        <p className="stage-subtitle">
          Вы прошли все этапы урока «{content.title.replace(/^\p{Extended_Pictographic}\s*/u, "")}». Вот ваши результаты:
        </p>

        <div className="complete-stats-row">
          <div className="result-summary-item">
            <strong>
              <AnimatedNumber value={content.vocabulary.length} suffix="" startDelay={vocabDelay} duration={perStatMs} />
            </strong>
            <span>слов изучено</span>
          </div>

          {ringStats.map((stat) => {
            if (stat.value === null) {
              return (
                <div className="stat-ring-card" key={stat.key}>
                  <div className="stat-ring-wrap">
                    <div className="stat-ring-value">—</div>
                  </div>
                  <span className="stat-ring-label">{stat.label}</span>
                </div>
              );
            }
            const startDelay = animatedIndex * perStatMs;
            animatedIndex += 1;
            return (
              <AnimatedRingStat
                key={stat.key}
                value={stat.value}
                label={stat.label}
                startDelay={startDelay}
                duration={perStatMs}
                color={stat.color}
              />
            );
          })}
        </div>

        <div className="stage-footer split">
          <Link to="/" className="btn btn-secondary">
            На главную
          </Link>
        </div>
      </div>
    </div>
  );
}
