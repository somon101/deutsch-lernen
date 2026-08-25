import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/auth/user.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/profile_gamification_repository.dart';

const _cefrLevels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

/// Fixed brand palette for the shareable profile card — deliberately NOT
/// `context.profileColors` (which swaps light/dark with the app's own
/// theme). The card must render identically regardless of the app's theme,
/// so every color here is a literal from the design handoff.
class _QrCardPalette {
  _QrCardPalette._();

  static const ink = Color(0xFF0E1638);
  static const inkSoft = Color(0xFF5B6285);
  static const blue = Color(0xFF2563EB);
  static const violet = Color(0xFF7C3AED);
  static const teal = Color(0xFF14D3B0);
  static const line = Color(0x170E1638); // rgba(14,22,56,.09)
  static const rungOff = Color(0x1A0E1638); // rgba(14,22,56,.10)
  static const rungLabelOff = Color(0x570E1638); // rgba(14,22,56,.34)
  static const sloganColor = Color(0x6B0E1638); // rgba(14,22,56,.42)
  static const cardGradientStart = Color(0xFFE3FAF3); // light mint
  static const cardGradientEnd = Color(0xFFE9E4FC); // light lavender
  static const qrPlateStart = Color(0xFFFDFEFF);
  static const qrPlateEnd = Color(0xFFE6EBFC);
}

/// The shareable "profile card": avatar/name header, CEFR level ladder,
/// a 3-column stats row, a scannable QR (center Lingora mark, error
/// correction level H so the logo doesn't break readability), and a
/// Lingora-branded footer with the user's public ID. Reused by both the
/// on-screen share sheet and the PNG rendered for the system share sheet
/// (via [repaintKey] + RepaintBoundary.toImage in the caller).
class ProfileQrCard extends StatelessWidget {
  const ProfileQrCard({
    super.key,
    required this.repaintKey,
    required this.user,
    required this.avatarUrl,
    required this.overview,
  });

  final GlobalKey repaintKey;
  final AppUser user;
  final String? avatarUrl;
  final ProfileGamificationOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fullName = '${user.firstName} ${user.lastName}'.trim();
    final qrData = 'https://lingora.app/u/${user.username}';

    return RepaintBoundary(
      key: repaintKey,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_QrCardPalette.cardGradientStart, _QrCardPalette.cardGradientEnd],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: _QrCardPalette.ink.withValues(alpha: 0.18), blurRadius: 32, offset: const Offset(0, 14))],
        ),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(user: user, avatarUrl: avatarUrl, fullName: fullName, learningLanguage: overview.learningLanguage),
            const SizedBox(height: 18),
            _LevelBlock(level: overview.level, l10n: l10n),
            const SizedBox(height: 18),
            _StatsRow(overview: overview, l10n: l10n),
            const SizedBox(height: 18),
            _QrBlock(qrData: qrData, username: user.username),
            const SizedBox(height: 16),
            _Footer(publicId: user.publicId, l10n: l10n),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.user, required this.avatarUrl, required this.fullName, required this.learningLanguage});

  final AppUser user;
  final String? avatarUrl;
  final String fullName;
  // TODO: подключить API — учебный язык пользователя не хранится на бэкенде.
  final String learningLanguage;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Avatar(avatarUrl: avatarUrl),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // FittedBox + maxLines:1 so a long (25+ char) name shrinks to
              // fit instead of overflowing or being clipped.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  fullName.isEmpty ? '@${user.username}' : fullName,
                  maxLines: 1,
                  style: GoogleFonts.playfairDisplay(fontSize: 25, fontWeight: FontWeight.w600, color: _QrCardPalette.ink, letterSpacing: -0.4),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '@${user.username} · $learningLanguage',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.golosText(fontSize: 12.5, fontWeight: FontWeight.w500, color: _QrCardPalette.inkSoft),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.avatarUrl});
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [BoxShadow(color: _QrCardPalette.ink.withValues(alpha: 0.22), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: (avatarUrl == null || avatarUrl!.isEmpty)
          ? const _AvatarSilhouette()
          : Image.network(
              avatarUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const _AvatarSilhouette(),
            ),
    );
  }
}

/// No-photo placeholder — never a blank tile.
class _AvatarSilhouette extends StatelessWidget {
  const _AvatarSilhouette();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFC9F5EA), Color(0xFFBFC6FB)],
        ),
      ),
      child: const Icon(Icons.person, color: Color(0xFF26305A), size: 46),
    );
  }
}

class _LevelBlock extends StatelessWidget {
  const _LevelBlock({required this.level, required this.l10n});

  final LevelProgress level;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final currentIndex = _cefrLevels.indexOf(level.code).clamp(0, _cefrLevels.length - 1);
    final nextLevel = currentIndex + 1 < _cefrLevels.length ? _cefrLevels[currentIndex + 1] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text.rich(
              TextSpan(
                style: GoogleFonts.golosText(fontSize: 13, fontWeight: FontWeight.w600, color: _QrCardPalette.ink),
                children: [
                  TextSpan(text: '${l10n.qrCardLevel} '),
                  // TODO: подключить API — уровень CEFR сейчас берётся из
                  // мок-репозитория геймификации.
                  TextSpan(text: level.code, style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
            Text(
              nextLevel == null ? l10n.qrCardMaxLevel : l10n.qrCardGoal(nextLevel, level.percent),
              style: GoogleFonts.golosText(fontSize: 12, color: _QrCardPalette.inkSoft),
            ),
          ],
        ),
        const SizedBox(height: 7),
        _Ladder(currentIndex: currentIndex, percent: level.percent),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < _cefrLevels.length; i++)
              Expanded(
                child: Text(
                  _cefrLevels[i],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.golosText(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: i <= currentIndex ? _QrCardPalette.violet : _QrCardPalette.rungLabelOff,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Ladder extends StatelessWidget {
  const _Ladder({required this.currentIndex, required this.percent});
  final int currentIndex;
  final int percent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _cefrLevels.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(child: _Rung(state: i < currentIndex ? _RungState.on : (i == currentIndex ? _RungState.current : _RungState.off), fillFraction: percent / 100)),
        ],
      ],
    );
  }
}

enum _RungState { on, current, off }

class _Rung extends StatelessWidget {
  const _Rung({required this.state, required this.fillFraction});
  final _RungState state;
  final double fillFraction;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 8,
        child: switch (state) {
          _RungState.on => const DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(colors: [_QrCardPalette.teal, _QrCardPalette.blue])),
            ),
          _RungState.off => const ColoredBox(color: _QrCardPalette.rungOff),
          _RungState.current => Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: _QrCardPalette.rungOff)),
                FractionallySizedBox(
                  widthFactor: fillFraction.clamp(0.0, 1.0),
                  child: const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [_QrCardPalette.blue, _QrCardPalette.violet]))),
                ),
              ],
            ),
        },
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.overview, required this.l10n});
  final ProfileGamificationOverview overview;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final numberFormat = NumberFormat.decimalPattern('ru');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: _QrCardPalette.line))),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // TODO: подключить API — серия дней сейчас из мок-репозитория.
            Expanded(child: _StatColumn(value: '🔥 ${overview.streakDays}', label: l10n.qrCardStreakLabel)),
            const VerticalDivider(width: 1, color: _QrCardPalette.line),
            // TODO: подключить API — место в рейтинге сейчас из мок-репозитория.
            Expanded(child: _StatColumn(value: '#${overview.rank.place}', label: l10n.qrCardRankLabel)),
            const VerticalDivider(width: 1, color: _QrCardPalette.line),
            // TODO: подключить API — число подписчиков сейчас из мок-репозитория.
            Expanded(child: _StatColumn(value: numberFormat.format(overview.social.followers), label: l10n.qrCardFollowersLabel)),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, maxLines: 1, style: GoogleFonts.golosText(fontSize: 19, fontWeight: FontWeight.w700, color: _QrCardPalette.ink, letterSpacing: -0.3)),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1, style: GoogleFonts.golosText(fontSize: 11, color: _QrCardPalette.inkSoft, height: 1.25)),
        ),
      ],
    );
  }
}

class _QrBlock extends StatelessWidget {
  const _QrBlock({required this.qrData, required this.username});
  final String qrData;
  final String username;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_QrCardPalette.qrPlateStart, _QrCardPalette.qrPlateEnd]),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 150,
            height: 150,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Error-correction level H is mandatory here: without it, the
                // logo overlay in the center would make the code unreadable.
                QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 150,
                  gapless: true,
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  backgroundColor: Colors.transparent,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _QrCardPalette.ink),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _QrCardPalette.ink),
                ),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.all(4),
                  child: Image.asset('assets/images/lingora_icon.png', fit: BoxFit.contain),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          Text('lingora.app/u/$username', style: GoogleFonts.golosText(fontSize: 12, fontWeight: FontWeight.w500, color: _QrCardPalette.inkSoft)),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.publicId, required this.l10n});
  final String publicId;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 14, bottom: 16),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _QrCardPalette.line))),
      child: Column(
        children: [
          Image.asset('assets/images/lingora_wordmark.png', height: 22, fit: BoxFit.contain),
          const SizedBox(height: 7),
          Text(
            l10n.qrCardSlogan.toUpperCase(),
            textAlign: TextAlign.center,
            style: GoogleFonts.golosText(fontSize: 9.5, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: _QrCardPalette.sloganColor),
          ),
          const SizedBox(height: 6),
          Text(
            publicId,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: _QrCardPalette.inkSoft),
          ),
        ],
      ),
    );
  }
}
