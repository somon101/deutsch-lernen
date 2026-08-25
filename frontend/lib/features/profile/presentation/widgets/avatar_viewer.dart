import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/auth/user.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/utils/image_crop.dart';
import '../profile_tokens.dart';
import 'qr_modal.dart';

enum _AvatarViewMode { normal, expanded }

/// The Telegram-style avatar area at the top of the profile screen: a small
/// circular photo by default (state 1), a full-width banner with overlaid
/// controls on tap or swipe-down (state 2), and — one more tap/swipe — a
/// true full-screen pinch-zoomable viewer pushed via [_FullscreenAvatarRoute]
/// (state 3, Hero-linked back to state 2's photo). Only reachable when the
/// user actually has a photo; with none, tapping just uploads one, same as
/// before this existed.
class AvatarViewer extends ConsumerStatefulWidget {
  const AvatarViewer({
    super.key,
    required this.user,
    required this.avatarUrl,
    required this.busy,
    required this.onPick,
    required this.onPicked,
    required this.onDelete,
    required this.isWide,
  });

  final AppUser user;
  final String avatarUrl;
  final bool busy;

  /// No-photo state: tapping the placeholder uploads one (existing flow,
  /// its own bottom-sheet choice of source).
  final VoidCallback onPick;

  /// Has-photo state, "Изменить фото" tile: picks straight from the
  /// gallery, no intermediate sheet, and hands the cropped bytes back.
  final Future<void> Function(Uint8List bytes, String filename) onPicked;

  final VoidCallback onDelete;
  final bool isWide;

  @override
  ConsumerState<AvatarViewer> createState() => _AvatarViewerState();
}

class _AvatarViewerState extends ConsumerState<AvatarViewer> {
  _AvatarViewMode _mode = _AvatarViewMode.normal;

  bool get _hasPhoto => widget.avatarUrl.isNotEmpty;
  String get _heroTag => 'avatar-${widget.user.id}';

  void _expand() => setState(() => _mode = _AvatarViewMode.expanded);
  void _collapse() => setState(() => _mode = _AvatarViewMode.normal);

  Future<void> _openFullscreen() async {
    await Navigator.of(context).push(_FullscreenAvatarRoute(imageUrl: widget.avatarUrl, heroTag: _heroTag));
  }

  void _handleTap() {
    if (!_hasPhoto) {
      widget.onPick();
      return;
    }
    if (_mode == _AvatarViewMode.normal) {
      _expand();
    } else {
      _openFullscreen();
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (!_hasPhoto) return;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity <= 200) return; // downward drag only
    if (_mode == _AvatarViewMode.normal) {
      _expand();
    } else {
      _openFullscreen();
    }
  }

  Future<void> _changePhotoFromGallery() async {
    final supportsImagePicker = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    Uint8List? bytes;
    if (supportsImagePicker) {
      final photo = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (photo == null) return;
      bytes = await photo.readAsBytes();
    } else {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      bytes = await file.readAsBytes();
    }
    await widget.onPicked(cropToSquareCenter(bytes), 'avatar.jpg');
    if (mounted) _collapse();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: ProfileMetrics.transition * 2,
      curve: ProfileMetrics.transitionCurve,
      alignment: Alignment.topCenter,
      child: _mode == _AvatarViewMode.expanded && _hasPhoto
          ? _ExpandedBanner(
              key: const ValueKey('expanded'),
              user: widget.user,
              avatarUrl: widget.avatarUrl,
              heroTag: _heroTag,
              onBack: _collapse,
              onTapPhoto: _handleTap,
              onVerticalDragEnd: _handleVerticalDragEnd,
              onChangePhoto: _changePhotoFromGallery,
            )
          : _NormalAvatar(
              key: const ValueKey('normal'),
              user: widget.user,
              avatarUrl: widget.avatarUrl,
              busy: widget.busy,
              isWide: widget.isWide,
              heroTag: _heroTag,
              hasPhoto: _hasPhoto,
              onTap: _handleTap,
              onVerticalDragEnd: _handleVerticalDragEnd,
              onDelete: widget.onDelete,
            ),
    );
  }
}

bool _isOnline(AppUser user) {
  final raw = user.lastActiveAt;
  if (raw == null) return false;
  final at = DateTime.tryParse(raw);
  if (at == null) return false;
  return DateTime.now().toUtc().difference(at.toUtc()) < const Duration(minutes: 5);
}

class _NormalAvatar extends StatelessWidget {
  const _NormalAvatar({
    super.key,
    required this.user,
    required this.avatarUrl,
    required this.busy,
    required this.isWide,
    required this.heroTag,
    required this.hasPhoto,
    required this.onTap,
    required this.onVerticalDragEnd,
    required this.onDelete,
  });

  final AppUser user;
  final String avatarUrl;
  final bool busy;
  final bool isWide;
  final String heroTag;
  final bool hasPhoto;
  final VoidCallback onTap;
  final GestureDragEndCallback onVerticalDragEnd;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    final size = isWide ? ProfileMetrics.avatarDesktop : ProfileMetrics.avatarMobile;
    final online = _isOnline(user);

    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          onVerticalDragEnd: onVerticalDragEnd,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              children: [
                Hero(
                  tag: heroTag,
                  child: CircleAvatar(
                    radius: size / 2,
                    backgroundColor: c.card,
                    backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl.isEmpty
                        ? Text(user.firstName.isNotEmpty ? user.firstName[0].toUpperCase() : '?', style: ProfileTypography.username(context))
                        : null,
                  ),
                ),
                if (busy) const Positioned.fill(child: Center(child: CircularProgressIndicator())),
                if (online)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(color: c.success, shape: BoxShape.circle, border: Border.all(color: c.bg, width: 2)),
                    ),
                  ),
                if (!hasPhoto)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle, border: Border.all(color: c.bg, width: 2)),
                      child: const Icon(Icons.camera_alt, size: 15, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('${user.firstName} ${user.lastName}'.trim(), style: ProfileTypography.username(context)),
        const SizedBox(height: 2),
        Text('@${user.username}', style: ProfileTypography.body(context).copyWith(color: c.accent)),
        if (user.bio != null && user.bio!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(user.bio!, textAlign: TextAlign.center, style: ProfileTypography.body(context).copyWith(color: c.textMuted)),
        ],
        if (hasPhoto)
          TextButton(
            onPressed: busy ? null : onDelete,
            child: Text('Удалить фото', style: ProfileTypography.caption(context).copyWith(color: c.danger)),
          ),
      ],
    );
  }
}

class _ExpandedBanner extends ConsumerWidget {
  const _ExpandedBanner({
    super.key,
    required this.user,
    required this.avatarUrl,
    required this.heroTag,
    required this.onBack,
    required this.onTapPhoto,
    required this.onVerticalDragEnd,
    required this.onChangePhoto,
  });

  final AppUser user;
  final String avatarUrl;
  final String heroTag;
  final VoidCallback onBack;
  final VoidCallback onTapPhoto;
  final GestureDragEndCallback onVerticalDragEnd;
  final VoidCallback onChangePhoto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.profileColors;
    final online = _isOnline(user);
    final bannerHeight = MediaQuery.sizeOf(context).height * 0.42;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(ProfileMetrics.cardRadius),
          child: SizedBox(
            height: bannerHeight,
            child: GestureDetector(
              onTap: onTapPhoto,
              onVerticalDragEnd: onVerticalDragEnd,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(tag: heroTag, child: Image.network(avatarUrl, fit: BoxFit.cover)),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: bannerHeight * 0.5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.75)],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 4,
                    right: 4,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: onBack),
                        IconButton(
                          icon: const Icon(Icons.qr_code_2, color: Colors.white),
                          onPressed: () => showQrModal(context, handle: user.id),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${user.firstName} ${user.lastName}'.trim(), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                        Text('@${user.username}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: online ? c.success : Colors.white38, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text(online ? 'в сети' : 'не в сети', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _ActionTile(icon: Icons.image_outlined, label: 'Изменить фото', onTap: onChangePhoto)),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionTile(
                icon: Icons.dark_mode_outlined,
                label: 'Тема',
                onTap: () => ref.read(themeModeProvider.notifier).toggle(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _ActionTile(icon: Icons.qr_code_2, label: 'QR-код', onTap: () => showQrModal(context, handle: user.id))),
          ],
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    return InkWell(
      borderRadius: BorderRadius.circular(ProfileMetrics.smallRadius),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(ProfileMetrics.smallRadius), border: Border.all(color: c.border)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c.accent, size: 22),
            const SizedBox(height: 6),
            Text(label, style: ProfileTypography.caption(context), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// State 3 — full-screen pinch-zoomable viewer. A custom PageRoute (rather
/// than a plain push of a Scaffold) so it owns its own opaque black
/// transition and the Hero grow-from-state-2 animation.
class _FullscreenAvatarRoute extends PageRoute<void> {
  _FullscreenAvatarRoute({required this.imageUrl, required this.heroTag});

  final String imageUrl;
  final String heroTag;

  @override
  Color? get barrierColor => Colors.black;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  bool get opaque => false;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => ProfileMetrics.transition * 2;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return _FullscreenAvatarView(imageUrl: imageUrl, heroTag: heroTag);
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    return FadeTransition(opacity: animation, child: child);
  }
}

class _FullscreenAvatarView extends StatefulWidget {
  const _FullscreenAvatarView({required this.imageUrl, required this.heroTag});
  final String imageUrl;
  final String heroTag;

  @override
  State<_FullscreenAvatarView> createState() => _FullscreenAvatarViewState();
}

class _FullscreenAvatarViewState extends State<_FullscreenAvatarView> {
  double _dragOffset = 0;

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _close,
          onVerticalDragUpdate: (details) => setState(() => _dragOffset += details.delta.dy),
          onVerticalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity > 300 || _dragOffset > 120) {
              _close();
            } else {
              setState(() => _dragOffset = 0);
            }
          },
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: _dragOffset == 0 ? ProfileMetrics.transition : Duration.zero,
                left: 0,
                right: 0,
                top: _dragOffset,
                bottom: -_dragOffset,
                child: Center(
                  child: Hero(
                    tag: widget.heroTag,
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Image.network(widget.imageUrl, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 4,
                child: SafeArea(
                  child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: _close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
