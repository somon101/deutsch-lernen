import { z } from "zod";

/**
 * Usernames are restricted to plain latin letters — no digits, spaces,
 * punctuation, cyrillic or emoji — and compared case-insensitively, so
 * "Ivan", "ivan" and "IVAN" all refer to the same account.
 */
export const USERNAME_PATTERN = /^[A-Za-z]+$/;
export const USERNAME_MIN = 3;
export const USERNAME_MAX = 32;

export const usernameSchema = z
  .string()
  .min(USERNAME_MIN, `Логин должен содержать не менее ${USERNAME_MIN} букв`)
  .max(USERNAME_MAX, `Логин должен содержать не более ${USERNAME_MAX} букв`)
  .regex(USERNAME_PATTERN, "Логин может содержать только латинские буквы (A-Z, a-z), без цифр, пробелов и знаков");

/** The value the case-insensitive unique constraint is checked against. */
export function normalizeUsername(username: string): string {
  return username.toLowerCase();
}
