// Tiny shared helper for one-shot UI sound effects (correct/incorrect answer,
// final report chime). Caches one Audio instance per URL so repeated calls
// (e.g. answering several questions) don't recreate the element each time.
const cache = new Map<string, HTMLAudioElement>();

// Browsers refuse audio.play() when the current page load hasn't had any
// user interaction yet — e.g. reloading straight onto a screen that tries to
// play a sound on mount, with no click/keydown/tap since the reload. When
// that happens the sound isn't dropped: it's queued and retried once, the
// moment the user interacts with the page at all (a standard, spec-compliant
// way to handle the autoplay restriction — not a policy bypass).
let pendingRetry: Set<HTMLAudioElement> | null = null;

function armRetryOnNextGesture(): void {
  if (pendingRetry) return;
  pendingRetry = new Set();

  const events = ["pointerdown", "keydown", "touchstart"] as const;
  const retry = () => {
    events.forEach((evt) => document.removeEventListener(evt, retry));
    const toPlay = pendingRetry;
    pendingRetry = null;
    toPlay?.forEach((audio) => {
      audio.play().catch(() => {
        // Blocked for some other reason — nothing more we can do.
      });
    });
  };

  events.forEach((evt) => document.addEventListener(evt, retry, { once: true }));
}

export function playSound(url: string): void {
  if (typeof Audio === "undefined") return;
  let audio = cache.get(url);
  if (!audio) {
    audio = new Audio(url);
    cache.set(url, audio);
  }
  audio.currentTime = 0;
  audio.play().catch(() => {
    armRetryOnNextGesture();
    pendingRetry?.add(audio!);
  });
}
