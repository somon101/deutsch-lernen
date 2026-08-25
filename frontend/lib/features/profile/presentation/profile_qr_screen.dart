import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_state.dart';
import '../../../l10n/app_localizations.dart';
import '../data/profile_gamification_repository.dart';
import 'profile_tokens.dart';
import 'widgets/profile_qr_card.dart';

/// Full-screen host for [ProfileQrCard] — the "share my profile" flow
/// reached from the QR icon on the profile header and the avatar viewer's
/// expanded banner. Pushed via go_router's `push` (not `go`), so the
/// system/app back button pops it normally.
class ProfileQrScreen extends ConsumerStatefulWidget {
  const ProfileQrScreen({super.key});

  @override
  ConsumerState<ProfileQrScreen> createState() => _ProfileQrScreenState();
}

class _ProfileQrScreenState extends ConsumerState<ProfileQrScreen> {
  final _repaintKey = GlobalKey();
  bool _rendering = false;
  bool _idCopied = false;

  Future<void> _share() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _rendering = true);
    try {
      final boundary = _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/profile_card.png');
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.qrCardShareFailed)));
      }
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  Future<void> _copyId(String publicId) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: publicId));
    if (!mounted) return;
    setState(() => _idCopied = true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.qrCardIdCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.profileColors;
    final user = ref.watch(authProvider).value;
    final overview = ref.watch(profileGamificationProvider);
    final isWide = MediaQuery.sizeOf(context).width >= ProfileMetrics.wideBreakpoint;

    if (user == null) return const SizedBox.shrink();

    final avatarUrl = ref.read(apiClientProvider).assetUrl(user.avatarUrl);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        title: Text(l10n.qrCardTitle, style: ProfileTypography.sectionTitle(context)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 420 : double.infinity),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(ProfileMetrics.pageMarginMobile),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProfileQrCard(
                    repaintKey: _repaintKey,
                    user: user,
                    avatarUrl: avatarUrl,
                    overview: overview,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: c.text, foregroundColor: c.bg, minimumSize: const Size.fromHeight(48)),
                          onPressed: _rendering ? null : _share,
                          icon: _rendering
                              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.bg))
                              : const Icon(Icons.ios_share),
                          label: Text(_rendering ? l10n.qrCardGenerating : l10n.qrCardShare),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 14)),
                        onPressed: () => _copyId(user.publicId),
                        icon: Icon(_idCopied ? Icons.check : Icons.copy, size: 18),
                        label: Text(l10n.qrCardCopyId),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
