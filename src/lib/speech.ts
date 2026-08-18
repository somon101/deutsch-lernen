import { assetUrl } from "../auth/api";

/**
 * Pronunciation playback for a German word.
 *
 * A word plays its uploaded recording when an admin has provided one. When it
 * hasn't, the browser's own speech synthesis reads the word instead, so every
 * word is audible without anyone having to record thousands of files. A real
 * recording always wins over the synthesised voice.
 */

// One Audio element per file, kept for the life of the page: the browser then
// serves repeat plays from its cache instead of re-downloading.
const audioCache = new Map<string, HTMLAudioElement>();

let cachedGermanVoice: SpeechSynthesisVoice | null | undefined;

function germanVoice(): SpeechSynthesisVoice | null {
  if (cachedGermanVoice !== undefined) return cachedGermanVoice;
  if (typeof speechSynthesis === "undefined") {
    cachedGermanVoice = null;
    return null;
  }
  const voices = speechSynthesis.getVoices();
  cachedGermanVoice = voices.find((v) => v.lang.toLowerCase().startsWith("de")) ?? null;
  return cachedGermanVoice;
}

if (typeof speechSynthesis !== "undefined") {
  // Voices load asynchronously in most browsers; re-read them once ready.
  speechSynthesis.addEventListener?.("voiceschanged", () => {
    cachedGermanVoice = undefined;
  });
}

export function canSynthesize(): boolean {
  return typeof speechSynthesis !== "undefined" && typeof SpeechSynthesisUtterance !== "undefined";
}

/** Reads a German word aloud with the browser's built-in voice. */
export function speakGerman(word: string): void {
  if (!canSynthesize()) return;
  speechSynthesis.cancel();
  const utterance = new SpeechSynthesisUtterance(word);
  utterance.lang = "de-DE";
  const voice = germanVoice();
  if (voice) utterance.voice = voice;
  utterance.rate = 0.9;
  speechSynthesis.speak(utterance);
}

function playFile(url: string): Promise<void> {
  let audio = audioCache.get(url);
  if (!audio) {
    audio = new Audio(url);
    audio.preload = "auto";
    audioCache.set(url, audio);
  }
  audio.currentTime = 0;
  return audio.play();
}

/**
 * Plays the recording if there is one, otherwise falls back to synthesis.
 * Never throws — a word that cannot be voiced simply stays silent.
 */
export async function playWord(word: string, audioUrl?: string): Promise<void> {
  const src = assetUrl(audioUrl);
  if (src) {
    try {
      await playFile(src);
      return;
    } catch {
      // Recording missing or blocked — fall through to the synthesised voice.
    }
  }
  speakGerman(word);
}

/** Warms the browser cache so the first click plays without a delay. */
export function preloadWordAudio(urls: (string | undefined)[]): void {
  for (const url of urls) {
    const src = assetUrl(url);
    if (!src || audioCache.has(src)) continue;
    const audio = new Audio(src);
    audio.preload = "auto";
    audioCache.set(src, audio);
  }
}
