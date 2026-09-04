import 'package:flutter/material.dart';

import 'seeded_random.dart';

/// A per-person avatar color, deterministic from their identity (§
/// leaderboard redesign, 2026-09-04) — the same user always gets the same
/// color everywhere they appear (podium, list row, search result), instead
/// of every avatar-without-a-photo sharing one flat theme color like
/// before. Stays theme-derived rather than a hardcoded palette: rotates the
/// current theme's own primary hue by an angle taken from [identity]'s hash
/// (reusing this codebase's existing FNV-1a `hashString`, not Dart's own
/// String.hashCode, which isn't guaranteed stable across platforms), so it
/// still respects light/dark automatically and never needs its own
/// palette to keep in sync with theme changes.
Color avatarColorFor(String identity, ColorScheme scheme) {
  final hue = HSLColor.fromColor(scheme.primary).hue;
  final rotated = (hue + (hashString(identity) % 360)) % 360;
  return HSLColor.fromColor(scheme.primary).withHue(rotated).toColor();
}
