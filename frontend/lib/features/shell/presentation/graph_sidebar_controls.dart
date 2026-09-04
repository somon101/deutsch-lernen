import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One block type a graph node can be, for the "+ add block" tool group —
/// mirrors lesson_graph_editor.dart's own `_nodeStyle` map keys exactly
/// (vocabulary/material/video/audio/minitest/practice/review); duplicated
/// here (not imported) only because the icons/labels need to render inside
/// AppShell's `_NavRail`, which must not depend on the admin course-builder
/// feature — the graph editor is still the only place that ever populates
/// [graphSidebarActionsProvider], this is just the shape it hands over.
class GraphSidebarBlockType {
  const GraphSidebarBlockType({required this.type, required this.label, required this.icon});
  final String type;
  final String label;
  final IconData icon;
}

/// Everything AppShell's `_NavRail` needs to render the graph editor's
/// tools (§ graph editor layout, 2026-09-04) — populated by
/// LessonGraphEditor while it's mounted and wide-laid-out, cleared the
/// moment it isn't (narrow fallback, a different lesson, or navigating
/// away entirely). The rail never contains any graph-editing logic itself;
/// every callback here is owned and executed by LessonGraphEditor exactly
/// as before, just invoked from a different place on screen.
class GraphSidebarActions {
  const GraphSidebarActions({
    required this.blockTypes,
    required this.busy,
    required this.connecting,
    required this.onAdd,
    required this.onToggleConnect,
    required this.onExit,
    required this.onOpenLessonSettings,
    required this.onOpenRoute,
  });

  final List<GraphSidebarBlockType> blockTypes;
  final bool busy;
  final bool connecting;
  final ValueChanged<String> onAdd;
  final VoidCallback onToggleConnect;
  final VoidCallback onExit;
  final VoidCallback onOpenLessonSettings;
  final VoidCallback onOpenRoute;
}

/// Null whenever no graph editor is currently showing (the overwhelmingly
/// common case — every other screen in the app).
final graphSidebarActionsProvider = StateProvider<GraphSidebarActions?>((ref) => null);
