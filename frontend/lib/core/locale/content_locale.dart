/// Course CONTENT locale (§ course content language, 2026-09-04) — which
/// instructional-language variant of a course's own text/media is shown.
/// Deliberately separate from `locale_provider.dart`'s system UI language:
/// the two must be free to change independently (see backend's
/// app/services/content_locale.py for the full rationale). Storage is
/// `AppUser.contentLocale`, synced through the existing `/api/me/` profile
/// endpoint (features/profile/data/profile_repository.dart) — the same
/// mechanism `selectedLanguageId` already uses, not a second parallel one.
const supportedContentLocales = ['ru', 'tg'];
const defaultContentLocale = 'ru';
