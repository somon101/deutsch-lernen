import '../../../l10n/app_localizations.dart';

/// Exact port of src/progress/types.ts's stage machinery — same 8 fixed
/// stages, same order, same unlock rule (a stage is unlocked iff the
/// immediately-preceding one is complete).
enum Stage { vocabulary, material, video, minitest, audio, practice, review, complete }

const stageOrder = Stage.values;

/// A function, not the `const Map<Stage, String>` this used to be — a const
/// expression can't hold a locale-dependent value (§ interface localization,
/// 2026-09-03), so the label is looked up fresh from the current
/// AppLocalizations instead of frozen at compile time.
String stageLabel(Stage stage, AppLocalizations l10n) => switch (stage) {
      Stage.vocabulary => l10n.stageVocabulary,
      Stage.material => l10n.stageMaterial,
      Stage.video => l10n.stageVideo,
      Stage.minitest => l10n.stageMinitest,
      Stage.audio => l10n.stageAudio,
      Stage.practice => l10n.stagePractice,
      Stage.review => l10n.stageReview,
      Stage.complete => l10n.stageComplete,
    };

Stage? stageFromId(String id) {
  for (final s in Stage.values) {
    if (s.name == id) return s;
  }
  return null;
}

bool isStageUnlocked(Set<Stage> completedStages, Stage stage) {
  final idx = stageOrder.indexOf(stage);
  if (idx <= 0) return true;
  return completedStages.contains(stageOrder[idx - 1]);
}

bool isStageComplete(Set<Stage> completedStages, Stage stage) => completedStages.contains(stage);

Stage nextIncompleteStage(Set<Stage> completedStages) {
  for (final stage in stageOrder) {
    if (!completedStages.contains(stage)) return stage;
  }
  return Stage.complete;
}

double courseProgressRatio(Set<Stage>? completedStages) {
  if (completedStages == null) return 0;
  final total = stageOrder.length - 1; // "complete" itself isn't a learning stage
  final done = completedStages.where((s) => s != Stage.complete).length;
  return total == 0 ? 0 : done / total;
}
