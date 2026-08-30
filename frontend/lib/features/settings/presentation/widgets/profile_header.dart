import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../core/auth/user.dart';
import '../../../profile/presentation/profile_tokens.dart';

/// Big centered avatar + name + @username + bio, used at the top of
/// SettingsScreen. Tapping anywhere on the avatar (including the camera
/// badge) opens the avatar picker sheet — per the spec, changing the photo
/// doesn't require going into Personal Details first.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.user,
    required this.avatarUrl,
    required this.busy,
    required this.onAvatarTap,
  });

  final AppUser user;
  final String avatarUrl;
  final bool busy;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    final l10n = AppLocalizations.of(context);
    final bio = user.bio;
    const size = ProfileMetrics.avatarDesktop - 10; // 110px per the spec

    return Column(
      children: [
        GestureDetector(
          onTap: busy ? null : onAvatarTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: size / 2,
                  backgroundColor: c.card,
                  // Disk-persisted (caching plan, 2026-08-29) — shows the
                  // last-downloaded avatar instantly, even offline.
                  backgroundImage: avatarUrl.isNotEmpty ? CachedNetworkImageProvider(avatarUrl) : null,
                  child: avatarUrl.isEmpty
                      ? Text(user.firstName.isNotEmpty ? user.firstName[0].toUpperCase() : '?', style: ProfileTypography.username(context))
                      : null,
                ),
                if (busy) const Positioned.fill(child: Center(child: CircularProgressIndicator())),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle, border: Border.all(color: c.bg, width: 2)),
                    child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('${user.firstName} ${user.lastName}'.trim(), style: ProfileTypography.username(context)),
        const SizedBox(height: 2),
        Text('@${user.username}', style: ProfileTypography.body(context).copyWith(color: c.textMuted)),
        const SizedBox(height: 8),
        Text(
          bio == null || bio.isEmpty ? l10n.personalDetailsBioPlaceholder : bio,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: ProfileTypography.body(context).copyWith(color: c.textMuted),
        ),
      ],
    );
  }
}
