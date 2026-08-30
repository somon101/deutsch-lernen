import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/auth/online_status_provider.dart';
import '../../../../core/auth/user.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/utils/image_crop.dart';
import '../profile_tokens.dart';

enum _AvatarViewMode { normal, expanded }

/// Tap + vertical-swipe detection for a widget that lives inside a
/// SingleChildScrollView. A plain GestureDetector's onVerticalDragEnd would
/// almost never fire here — the ancestor Scrollable wins the gesture arena
/// for vertical drags before this widget's own pan recognizer gets a
/// chance. Listener sidesteps that: it receives every raw pointer event
/// that hits it regardless of which higher-level gesture recognizer "wins"
/// the arena, so a manual start/end position comparison reliably detects
/// the swipe. Tap keeps using GestureDetector, which negotiates fine on
/// its own (a tap has no ancestor competing for it).
class _SwipeArea extends StatefulWidget {
  const _SwipeArea({required this.onTap, required this.onVerticalSwipe, required this.child});

  final VoidCallback onTap;

  /// Positive = swiped down, negative = swiped up.
  final ValueChanged<double> onVerticalSwipe;
  final Widget child;

  @override
  State<_SwipeArea> createState() => _SwipeAreaState();
}

class _SwipeAreaState extends State<_SwipeArea> {
  double? _startY;
  static const _threshold = 40.0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) => _startY = event.position.dy,
      onPointerUp: (event) {
        final start = _startY;
        _startY = null;
        if (start == null) return;
        final dy = event.position.dy - start;
        if (dy.abs() > _threshold) widget.onVerticalSwipe(dy);
      },
      child: GestureDetector(onTap: widget.onTap, child: widget.child),
    );
  }
}

/// The Telegram-style avatar area at the top of the profile screen: a small
/// circular photo by default (state 1), a full-width banner with controls
/// overlaid *on* the photo on tap or swipe-down (state 2, swipe-up to
/// collapse back), and — one more tap on the photo — a true full-screen
/// pinch-zoomable viewer (state 3, Hero-linked back to state 2's photo).
///
/// [onExpandedChanged] lets the parent screen hide its own header while
/// state 2 is showing — that header has its own theme/QR icons, which
/// would otherwise be duplicated by this widget's overlay controls.
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
    required this.onExpandedChanged,
  });

  final AppUser user;
  final String avatarUrl;
  final bool busy;

  /// No-photo state: tapping the placeholder uploads one (existing flow,
  /// its own bottom-sheet choice of source).
  final VoidCallback onPick;

  /// Has-photo state, the change-photo overlay icon: picks straight from
  /// the gallery, no intermediate sheet, and hands the cropped bytes back.
  final Future<void> Function(Uint8List bytes, String filename) onPicked;

  final VoidCallback onDelete;
  final bool isWide;
  final ValueChanged<bool> onExpandedChanged;

  @override
  ConsumerState<AvatarViewer> createState() => _AvatarViewerState();
}

class _AvatarViewerState extends ConsumerState<AvatarViewer> {
  _AvatarViewMode _mode = _AvatarViewMode.normal;

  // Render.com's free tier has no persistent disk — uploaded avatars can
  // vanish from the filesystem on a redeploy while the DB still has the old
  // URL. Rather than let that show as a blank/broken image, a load failure
  // here demotes straight to "no photo" (initials circle, states 2/3
  // unreachable) exactly like a genuinely missing avatarUrl would.
  bool _loadFailed = false;

  bool get _hasPhoto => widget.avatarUrl.isNotEmpty && !_loadFailed;
  String get _heroTag => 'avatar-${widget.user.id}';

  void _setMode(_AvatarViewMode mode) {
    setState(() => _mode = mode);
    widget.onExpandedChanged(mode == _AvatarViewMode.expanded);
  }

  void _expand() => _setMode(_AvatarViewMode.expanded);
  void _collapse() => _setMode(_AvatarViewMode.normal);

  void _onImageError() {
    if (_loadFailed) return;
    setState(() => _loadFailed = true);
    widget.onExpandedChanged(false);
  }

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

  /// Positive [dy] = swiped down, negative = swiped up (see _SwipeArea —
  /// raw pointer tracking, not GestureDetector's onVerticalDragEnd, which
  /// this widget sits nested inside a SingleChildScrollView and would
  /// almost never actually receive: a Scrollable ancestor wins the gesture
  /// arena for vertical drags before a child pan recognizer gets a look.
  void _handleVerticalSwipe(double dy) {
    if (_mode == _AvatarViewMode.normal) {
      if (_hasPhoto && dy > 0) _expand(); // swipe down
    } else {
      if (dy < 0) _collapse(); // swipe up
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
    setState(() => _loadFailed = false);
    await widget.onPicked(cropToSquareCenter(bytes), 'avatar.jpg');
    if (mounted) _collapse();
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(isAppForegroundProvider);
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
              online: online,
              onBack: _collapse,
              onTapPhoto: _handleTap,
              onVerticalSwipe: _handleVerticalSwipe,
              onChangePhoto: _changePhotoFromGallery,
              onImageError: _onImageError,
            )
          : _NormalAvatar(
              key: const ValueKey('normal'),
              user: widget.user,
              avatarUrl: widget.avatarUrl,
              busy: widget.busy,
              isWide: widget.isWide,
              heroTag: _heroTag,
              hasPhoto: _hasPhoto,
              online: online,
              onTap: _handleTap,
              onVerticalSwipe: _handleVerticalSwipe,
              onDelete: widget.onDelete,
              onImageError: _onImageError,
            ),
    );
  }
}

/// Circle avatar that falls back to initials on a failed image load
/// (instead of Flutter's default red error box / a blank circle) and
/// reports the failure upward via [onError].
class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({required this.avatarUrl, required this.initials, required this.size, required this.onError});

  final String avatarUrl;
  final String initials;
  final double size;
  final VoidCallback onError;

  Widget _placeholder(BuildContext context) {
    final c = context.profileColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.card, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initials, style: ProfileTypography.username(context)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (avatarUrl.isEmpty) return _placeholder(context);
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: avatarUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Shows the last-downloaded copy from disk instantly, even offline
        // (caching plan, 2026-08-29) — Image.network only ever cached in
        // memory, gone the moment the app restarted.
        placeholder: (context, url) => _placeholder(context),
        errorWidget: (context, url, error) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onError());
          return _placeholder(context);
        },
      ),
    );
  }
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
    required this.online,
    required this.onTap,
    required this.onVerticalSwipe,
    required this.onDelete,
    required this.onImageError,
  });

  final AppUser user;
  final String avatarUrl;
  final bool busy;
  final bool isWide;
  final String heroTag;
  final bool hasPhoto;
  final bool online;
  final VoidCallback onTap;
  final ValueChanged<double> onVerticalSwipe;
  final VoidCallback onDelete;
  final VoidCallback onImageError;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    final size = isWide ? ProfileMetrics.avatarDesktop : ProfileMetrics.avatarMobile;
    final initials = user.firstName.isNotEmpty ? user.firstName[0].toUpperCase() : '?';

    return Column(
      children: [
        _SwipeArea(
          onTap: onTap,
          onVerticalSwipe: onVerticalSwipe,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              children: [
                Hero(tag: heroTag, child: _AvatarCircle(avatarUrl: avatarUrl, initials: initials, size: size, onError: onImageError)),
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
    required this.online,
    required this.onBack,
    required this.onTapPhoto,
    required this.onVerticalSwipe,
    required this.onChangePhoto,
    required this.onImageError,
  });

  final AppUser user;
  final String avatarUrl;
  final String heroTag;
  final bool online;
  final VoidCallback onBack;
  final VoidCallback onTapPhoto;
  final ValueChanged<double> onVerticalSwipe;
  final VoidCallback onChangePhoto;
  final VoidCallback onImageError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.profileColors;
    final themeMode = ref.watch(themeModeProvider);
    final bannerHeight = MediaQuery.sizeOf(context).height * 0.42;

    return ClipRRect(
      borderRadius: BorderRadius.circular(ProfileMetrics.cardRadius),
      child: SizedBox(
        height: bannerHeight,
        child: _SwipeArea(
          onTap: onTapPhoto,
          onVerticalSwipe: onVerticalSwipe,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: heroTag,
                child: CachedNetworkImage(
                  imageUrl: avatarUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => ColoredBox(color: c.card),
                  errorWidget: (context, url, error) {
                    WidgetsBinding.instance.addPostFrameCallback((_) => onImageError());
                    return ColoredBox(color: c.card);
                  },
                ),
              ),
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
              // Every control lives inside the photo itself — icon-only, no
              // labels — so the screen's own header (title + theme/QR) can
              // just disappear in this state instead of duplicating them.
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _CircleIconButton(icon: Icons.arrow_back, onTap: onBack),
                    Row(
                      children: [
                        _CircleIconButton(icon: Icons.camera_alt_outlined, onTap: onChangePhoto),
                        const SizedBox(width: 8),
                        _CircleIconButton(
                          icon: themeMode == ThemeMode.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                          onTap: () => ref.read(themeModeProvider.notifier).toggle(),
                        ),
                        const SizedBox(width: 8),
                        _CircleIconButton(icon: Icons.qr_code_2, onTap: () => context.push('/profile/qr')),
                      ],
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
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, color: Colors.white, size: 20)),
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
                      child: CachedNetworkImage(imageUrl: widget.imageUrl, fit: BoxFit.contain),
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
