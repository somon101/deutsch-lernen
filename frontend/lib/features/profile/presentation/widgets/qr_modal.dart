import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../profile_tokens.dart';

/// Profile "share" sheet, opened from the QR icon in the profile header.
///
/// No QR-generation package is in the project yet (only cupertino_icons is
/// bundled) — rather than hand-roll a fake, unscannable pattern that looks
/// like a real code, this shows a placeholder tile plus a working
/// copy-link action. Add `qr_flutter` (small, no native deps) to render an
/// actual scannable code here.
Future<void> showQrModal(BuildContext context, {required String handle}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _QrModalSheet(handle: handle),
  );
}

class _QrModalSheet extends StatefulWidget {
  const _QrModalSheet({required this.handle});
  final String handle;

  @override
  State<_QrModalSheet> createState() => _QrModalSheetState();
}

class _QrModalSheetState extends State<_QrModalSheet> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(ProfileMetrics.cardPadding),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(ProfileMetrics.cardRadius),
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Поделиться профилем', style: ProfileTypography.sectionTitle(context)),
            const SizedBox(height: 20),
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(ProfileMetrics.smallRadius),
                border: Border.all(color: c.border),
              ),
              child: Icon(Icons.qr_code_2, size: 96, color: c.textMuted),
            ),
            const SizedBox(height: 16),
            Text(widget.handle, style: ProfileTypography.body(context).copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Сканируемый QR появится после подключения генератора кодов', textAlign: TextAlign.center, style: ProfileTypography.caption(context)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: Colors.white),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.handle));
                  if (!mounted) return;
                  setState(() => _copied = true);
                },
                icon: Icon(_copied ? Icons.check : Icons.link),
                label: Text(_copied ? 'Скопировано' : 'Скопировать ссылку'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
