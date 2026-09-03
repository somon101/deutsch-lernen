import 'package:flutter/material.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/cache/image_prefetch.dart';
import '../../../../l10n/app_localizations.dart';

/// Pulls a lesson's word photos onto the device before the lesson opens
/// (§ pre-download word photos, 2026-09-02).
///
/// Shown only when there is actually something to fetch. A lesson opened
/// before has its photos on disk already, so [openLesson] finds nothing
/// missing and navigates straight through — the sheet never appears, which
/// is the behaviour a second visit should have.
///
/// Cancelling closes the sheet and does NOT open the lesson: a learner who
/// backs out of a download meant to back out, not to walk into the version
/// of the lesson they were trying to avoid.
class _DownloadSheet extends StatefulWidget {
  const _DownloadSheet({required this.urls, required this.prefetcher});

  final List<String> urls;
  final ImagePrefetcher prefetcher;

  @override
  State<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<_DownloadSheet> {
  int _done = 0;
  int _total = 0;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _total = widget.urls.length;
    _run();
  }

  Future<void> _run() async {
    final failed = await widget.prefetcher.download(
      widget.urls,
      onProgress: (done, total) {
        if (!mounted || _cancelled) return;
        setState(() {
          _done = done;
          _total = total;
        });
      },
      isCancelled: () => _cancelled,
    );
    if (!mounted || _cancelled) return;
    // Even a partial failure opens the lesson: the photos that did arrive
    // are on disk, and the ones that didn't fall back to loading normally.
    Navigator.of(context).pop(failed >= 0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = _total == 0 ? null : _done / _total;
    return PopScope(
      canPop: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.lessonDownloadTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              l10n.lessonDownloadSubtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: value, minHeight: 6),
            ),
            const SizedBox(height: 10),
            Text(l10n.lessonDownloadProgress(_done, _total), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  setState(() => _cancelled = true);
                  Navigator.of(context).pop(false);
                },
                child: Text(l10n.cancel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Downloads what this lesson needs, then runs [open].
///
/// Returns without opening only when the learner cancels. Anything else —
/// nothing to download, a failed photo, no photos at all — still opens the
/// lesson: a picture must never be the reason a lesson can't be started.
Future<void> openLessonWithPhotos(
  BuildContext context, {
  required ApiClient api,
  required List<String> imageUrls,
  required VoidCallback open,
  ImagePrefetcher? prefetcher,
}) async {
  final fetcher = prefetcher ?? ImagePrefetcher();
  final resolved = [
    for (final u in imageUrls)
      if (api.assetUrl(u).isNotEmpty) api.assetUrl(u),
  ];

  List<String> missing;
  try {
    missing = await fetcher.missing(resolved);
  } catch (_) {
    missing = const [];
  }
  if (!context.mounted) return;

  if (missing.isEmpty) {
    open();
    return;
  }

  final proceed = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _DownloadSheet(urls: missing, prefetcher: fetcher),
  );
  if (proceed == true && context.mounted) open();
}
