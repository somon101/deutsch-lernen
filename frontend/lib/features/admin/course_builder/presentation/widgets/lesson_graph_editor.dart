import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shell/presentation/graph_sidebar_controls.dart';
import '../../../admin_tokens.dart';
import '../../../widgets/admin_feedback.dart';
import '../../data/builder_repository.dart';
import '../../domain/builder_domain.dart';
import '../builder_lesson_edit_screen.dart' show LessonNameCard;
import 'block_editor.dart';
import 'material_block_editor.dart';
import 'media_editor.dart';
import 'vocabulary_editor.dart';

/// Free-form lesson graph canvas (§ lesson graph, 2026-09-03) — replaces the
/// fixed 8-step rail for any lesson that has been converted (see
/// [BuilderLessonEditScreen]'s branch on `lesson.graph != null`). A node
/// wraps EXISTING content by reference (a Material, a LessonBlock, or — for
/// vocabulary/video/audio — nothing at all/its own mediaUrl); this widget's
/// own job is topology only (add/move/connect/delete nodes and flow edges)
/// — every node's actual CONTENT is edited by the exact same widgets the old
/// rail already used (VocabularyEditor/MaterialBlockEditor/MediaEditor/
/// BlockEditor), unmodified in behavior, just parameterized by this node
/// instead of a fixed stage key.
class LessonGraphEditor extends ConsumerStatefulWidget {
  const LessonGraphEditor({super.key, required this.courseId, required this.lesson, required this.languageId, required this.onReload});

  final String courseId;
  final AdminLesson lesson;
  final String? languageId;
  final VoidCallback onReload;

  @override
  ConsumerState<LessonGraphEditor> createState() => _LessonGraphEditorState();
}

const _nodeWidth = 200.0;
const _nodeHeight = 76.0;

const Map<String, ({String label, IconData icon, Color color})> _nodeStyle = {
  'vocabulary': (label: 'Слова', icon: Icons.style_outlined, color: Color(0xFF2F6FED)),
  'material': (label: 'Материал', icon: Icons.menu_book_outlined, color: Color(0xFF8A4FE0)),
  'video': (label: 'Видео', icon: Icons.movie_outlined, color: Color(0xFFE5484D)),
  'audio': (label: 'Аудио', icon: Icons.headphones_outlined, color: Color(0xFFE08A2F)),
  'minitest': (label: 'Мини-тест', icon: Icons.quiz_outlined, color: Color(0xFF1FA974)),
  'practice': (label: 'Практика', icon: Icons.fitness_center_outlined, color: Color(0xFF1B9C9C)),
  'review': (label: 'Закрепление', icon: Icons.flag_outlined, color: Color(0xFF4A5CF0)),
};

/// 1-based "which number in the walk-through" per node id (§ lesson graph
/// follow-up, 2026-09-03) — the backend now refuses a second incoming or
/// outgoing flow edge on any node (add_edge), so the graph is always a set
/// of simple chains, never a merge/branch; this is exactly the topological
/// flatten the student runner computes (see lesson_runner's flattenGraph),
/// duplicated here (small and self-contained) so the canvas can show a
/// teacher the same order live while editing, right on each block.
/// Roots (no incoming edge) are walked in the server's own node order
/// (created-at, see services/lesson_graph.py's _real_nodes) so numbering is
/// stable across reloads.
Map<String, int> _computeOrder(AdminLessonGraph graph) {
  final hasIncoming = {for (final e in graph.edges) e.toNodeId};
  final outgoing = {for (final e in graph.edges) e.fromNodeId: e.toNodeId};
  final order = <String, int>{};
  var next = 1;
  void walk(String id) {
    var current = id;
    while (!order.containsKey(current)) {
      order[current] = next++;
      final child = outgoing[current];
      if (child == null) break;
      current = child;
    }
  }

  for (final n in graph.nodes) {
    if (!hasIncoming.contains(n.id)) walk(n.id);
  }
  // Defensive: a node that somehow wasn't reached (e.g. mid-edit transient
  // state) still gets a number rather than showing blank.
  for (final n in graph.nodes) {
    if (!order.containsKey(n.id)) order[n.id] = next++;
  }
  return order;
}

class _LessonGraphEditorState extends ConsumerState<LessonGraphEditor> {
  String? _selectedNodeId;
  String? _connectFromId;
  bool _busy = false;
  final Map<String, Offset> _dragOverride = {};

  AdminLessonGraph get _graph => widget.lesson.graph!;

  BuilderRepository get _repo => ref.read(builderRepositoryProvider);

  Offset _posOf(AdminGraphNode n) => _dragOverride[n.id] ?? Offset(n.posX, n.posY);

  Future<void> _run(Future<void> Function() action, {String? errorMessage}) async {
    setState(() => _busy = true);
    try {
      await action();
      widget.onReload();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, errorMessage ?? 'Не удалось выполнить действие');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Offset _nextFreeSpot() {
    if (_graph.nodes.isEmpty) return const Offset(40, 40);
    final maxX = _graph.nodes.map((n) => n.posX).reduce((a, b) => a > b ? a : b);
    return Offset(maxX + _nodeWidth + 60, 40);
  }

  Future<void> _addNode(String type) async {
    final spot = _nextFreeSpot();
    await _run(() async {
      final node = await _repo.addGraphNode(widget.courseId, widget.lesson.id, type: type, posX: spot.dx, posY: spot.dy);
      setState(() => _selectedNodeId = node.id);
    });
  }

  Future<void> _onNodeTap(AdminGraphNode node) async {
    if (_connectFromId != null) {
      // Pre-existing gap in this state machine, not something the sidebar
      // move introduced (§ graph editor layout, 2026-09-04 verification
      // finding): connect mode toggled with no node pre-selected sets
      // `_connectFromId` to '' as a "waiting for the source" sentinel (see
      // onToggleConnect and the two distinct hint strings below), but
      // nothing ever actually captured a node tap INTO that sentinel — the
      // very next tap fell straight into the "create the edge" branch
      // below with an empty `from`, which the backend correctly rejected.
      if (_connectFromId!.isEmpty) {
        setState(() => _connectFromId = node.id);
        return;
      }
      final from = _connectFromId!;
      setState(() => _connectFromId = null);
      if (from == node.id) return;
      await _run(() => _repo.addGraphEdge(widget.courseId, widget.lesson.id, from, node.id), errorMessage: 'Не удалось создать связь');
      return;
    }
    setState(() => _selectedNodeId = node.id);
  }

  Future<void> _deleteNode(AdminGraphNode node) async {
    final ok = await confirmDialog(
      context,
      title: 'Удалить блок «${node.title}»?',
      message: 'Содержимое этого блока (материал, вопросы) удалится вместе с ним.',
    );
    if (!ok) return;
    await _run(() async {
      await _repo.deleteGraphNode(widget.courseId, widget.lesson.id, node.id);
      if (_selectedNodeId == node.id) _selectedNodeId = null;
    });
  }

  Future<void> _deleteEdge(AdminGraphEdge edge) async {
    await _run(() => _repo.deleteGraphEdge(widget.courseId, widget.lesson.id, edge.id));
  }

  // Mirrors the AppBar's own back button on BuilderLessonEditScreen exactly
  // (§ graph exit navigation, 2026-09-03) — canPop() first, else an explicit
  // context.go to the course editor. The graph is a widget swapped in by
  // lesson.graph != null, not a pushed route, so a bare Navigator.maybePop()
  // had nothing reliable of its own to pop: inside this app's ShellRoute
  // this either did nothing or left the builder on a screen the admin
  // didn't ask for, instead of the "back to the regular course editor"
  // behaviour the exit button is supposed to have.
  void _exit() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      context.go('/admin/builder/${widget.courseId}');
    }
  }

  void _toggleConnect() => setState(() => _connectFromId = _connectFromId == null ? (_selectedNodeId ?? '') : null);

  // Same LessonNameCard the pre-graph/linear-view screen already shows
  // inline, unmodified, just reached from the sidebar instead (§ graph
  // editor layout, 2026-09-04, change 2) — closes on its own × here, on a
  // tap outside, or on Esc (all three are the default showDialog/Dialog
  // route behavior, nothing extra to wire up).
  Future<void> _openLessonSettingsDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: AdminColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminMetrics.cardRadius)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(dialogContext).pop()),
                ),
                LessonNameCard(courseId: widget.courseId, lesson: widget.lesson),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Same _EdgeList this file already had inline at the bottom of the
  // canvas, unmodified, just in a dialog now (§ graph editor layout,
  // 2026-09-04, change 3).
  Future<void> _openRouteDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
              Flexible(child: SingleChildScrollView(child: _EdgeList(graph: _graph, onDelete: _deleteEdge))),
            ],
          ),
        ),
      ),
    );
  }

  // Best-effort (§ graph editor layout, 2026-09-04 verification finding —
  // a "Cannot use ref after the widget was disposed" console error was
  // reproduced 3/3 times specifically on the Граф→Линейный transition,
  // even though `mounted` is checked first below): whatever the exact
  // Riverpod-internal race is, this write is pure cleanup with nothing
  // downstream depending on it succeeding, so swallowing a disposal-timing
  // exception here is the same "never let a non-critical side effect
  // throw" convention already used elsewhere in this codebase (e.g.
  // ExerciseStage's answer-logging catch blocks) rather than something
  // requiring a user-visible error.
  void _clearSidebar() {
    try {
      ref.read(graphSidebarActionsProvider.notifier).state = null;
    } catch (_) {}
  }

  void _syncSidebar(bool isWide) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!isWide) {
        _clearSidebar();
        return;
      }
      try {
        ref.read(graphSidebarActionsProvider.notifier).state = GraphSidebarActions(
          blockTypes: [for (final entry in _nodeStyle.entries) GraphSidebarBlockType(type: entry.key, label: entry.value.label, icon: entry.value.icon)],
          busy: _busy,
          connecting: _connectFromId != null,
          onAdd: _addNode,
          onToggleConnect: _toggleConnect,
          onExit: _exit,
          onOpenLessonSettings: _openLessonSettingsDialog,
          onOpenRoute: _openRouteDialog,
        );
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    // Synchronous, not scheduled — ref is still valid here, and this is the
    // one moment that must not be missed: without it, the rail would keep
    // showing this lesson's graph tools after navigating away from it.
    _clearSidebar();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final selected = _selectedNodeId == null ? null : _graph.nodes.cast<AdminGraphNode?>().firstWhere((n) => n!.id == _selectedNodeId, orElse: () => null);

    final order = _computeOrder(_graph);

    final canvas = _GraphCanvas(
      graph: _graph,
      order: order,
      posOf: _posOf,
      connectFromId: _connectFromId,
      selectedNodeId: _selectedNodeId,
      onNodeTap: _onNodeTap,
      onNodeDragUpdate: (node, delta) => setState(() => _dragOverride[node.id] = _posOf(node) + delta),
      onNodeDragEnd: (node) {
        final pos = _dragOverride[node.id];
        if (pos != null) {
          _run(() => _repo.updateGraphNode(widget.courseId, widget.lesson.id, node.id, posX: pos.dx, posY: pos.dy));
        }
      },
    );

    _syncSidebar(isWide);

    if (!isWide) {
      final toolbar = _GraphToolbar(busy: _busy, connecting: _connectFromId != null, onAdd: _addNode, onToggleConnect: _toggleConnect, onExit: _exit);
      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          toolbar,
          const SizedBox(height: AdminMetrics.cardGap),
          if (_connectFromId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _connectFromId!.isEmpty ? 'Выберите блок-источник связи' : 'Выберите блок, к которому ведёт связь',
                style: AdminTypography.caption.copyWith(color: AdminColors.accent),
              ),
            ),
          Expanded(child: AdminCard(padding: EdgeInsets.zero, child: canvas)),
          const SizedBox(height: AdminMetrics.cardGap),
          _EdgeList(graph: _graph, onDelete: _deleteEdge),
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: body),
          if (selected != null) ...[
            const SizedBox(height: AdminMetrics.cardGap),
            SizedBox(
              height: 420,
              child: AdminCard(
                child: _NodeInspector(
                  courseId: widget.courseId,
                  lesson: widget.lesson,
                  node: selected,
                  languageId: widget.languageId,
                  onClose: () => setState(() => _selectedNodeId = null),
                  onDelete: () => _deleteNode(selected),
                  onReload: widget.onReload,
                ),
              ),
            ),
          ],
        ],
      );
    }

    // Wide layout (§ graph editor layout, 2026-09-04): the add-block/
    // connect/lesson/route/exit tools all live in AppShell's rail now (see
    // _syncSidebar above) — this body is just the connect-mode hint plus
    // the canvas itself, free to take almost the whole screen.
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_connectFromId != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _connectFromId!.isEmpty ? 'Выберите блок-источник связи' : 'Выберите блок, к которому ведёт связь',
              style: AdminTypography.caption.copyWith(color: AdminColors.accent),
            ),
          ),
        Expanded(child: AdminCard(padding: EdgeInsets.zero, child: canvas)),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: body),
        if (selected != null) ...[
          const SizedBox(width: AdminMetrics.cardGap),
          SizedBox(
            width: 380,
            height: double.infinity,
            child: AdminCard(
              child: _NodeInspector(
                courseId: widget.courseId,
                lesson: widget.lesson,
                node: selected,
                languageId: widget.languageId,
                onClose: () => setState(() => _selectedNodeId = null),
                onDelete: () => _deleteNode(selected),
                onReload: widget.onReload,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _GraphToolbar extends StatelessWidget {
  const _GraphToolbar({required this.busy, required this.connecting, required this.onAdd, required this.onToggleConnect, required this.onExit});
  final bool busy;
  final bool connecting;
  final ValueChanged<String> onAdd;
  final VoidCallback onToggleConnect;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final type in _nodeStyle.keys)
                OutlinedButton.icon(
                  onPressed: busy ? null : () => onAdd(type),
                  style: AdminButtonStyles.secondary(),
                  icon: Icon(_nodeStyle[type]!.icon, size: 16),
                  label: Text('+ ${_nodeStyle[type]!.label}'),
                ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                onPressed: busy ? null : onToggleConnect,
                style: connecting ? AdminButtonStyles.primary() : AdminButtonStyles.secondary(),
                icon: const Icon(Icons.arrow_right_alt, size: 18),
                label: Text(connecting ? 'Отменить соединение' : 'Соединить блоки'),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: onExit,
          style: AdminButtonStyles.text(),
          icon: const Icon(Icons.logout, size: 16),
          label: const Text('Выйти из графа'),
        ),
      ],
    );
  }
}

class _EdgeList extends StatelessWidget {
  const _EdgeList({required this.graph, required this.onDelete});
  final AdminLessonGraph graph;
  final ValueChanged<AdminGraphEdge> onDelete;

  String _labelFor(String nodeId) {
    final node = graph.nodes.cast<AdminGraphNode?>().firstWhere((n) => n!.id == nodeId, orElse: () => null);
    return node?.title ?? '?';
  }

  @override
  Widget build(BuildContext context) {
    if (graph.edges.isEmpty) {
      return Text('Связей ещё нет — соедините блоки, чтобы задать маршрут ученика.', style: AdminTypography.caption);
    }
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Маршрут (связи)', style: AdminTypography.fieldLabel),
          const SizedBox(height: 8),
          for (final edge in graph.edges)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(child: Text('${_labelFor(edge.fromNodeId)}  →  ${_labelFor(edge.toNodeId)}', style: AdminTypography.body)),
                  IconButton(
                    tooltip: 'Удалить связь',
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => onDelete(edge),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GraphCanvas extends StatelessWidget {
  const _GraphCanvas({
    required this.graph,
    required this.order,
    required this.posOf,
    required this.connectFromId,
    required this.selectedNodeId,
    required this.onNodeTap,
    required this.onNodeDragUpdate,
    required this.onNodeDragEnd,
  });

  final AdminLessonGraph graph;
  final Map<String, int> order;
  final Offset Function(AdminGraphNode) posOf;
  final String? connectFromId;
  final String? selectedNodeId;
  final ValueChanged<AdminGraphNode> onNodeTap;
  final void Function(AdminGraphNode, Offset delta) onNodeDragUpdate;
  final ValueChanged<AdminGraphNode> onNodeDragEnd;

  @override
  Widget build(BuildContext context) {
    double maxX = 800, maxY = 400;
    for (final n in graph.nodes) {
      final p = posOf(n);
      if (p.dx + _nodeWidth + 80 > maxX) maxX = p.dx + _nodeWidth + 80;
      if (p.dy + _nodeHeight + 80 > maxY) maxY = p.dy + _nodeHeight + 80;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AdminMetrics.cardRadius),
      child: ColoredBox(
        color: AdminColors.bg,
        child: InteractiveViewer(
          constrained: false,
          minScale: 0.4,
          maxScale: 2.0,
          boundaryMargin: const EdgeInsets.all(200),
          child: SizedBox(
            width: maxX,
            height: maxY,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _EdgePainter(
                      graph: graph,
                      posOf: posOf,
                    ),
                  ),
                ),
                for (final node in graph.nodes)
                  Positioned(
                    left: posOf(node).dx,
                    top: posOf(node).dy,
                    child: _NodeCard(
                      node: node,
                      number: order[node.id],
                      selected: node.id == selectedNodeId,
                      connecting: connectFromId == node.id,
                      onTap: () => onNodeTap(node),
                      onPanUpdate: (delta) => onNodeDragUpdate(node, delta),
                      onPanEnd: () => onNodeDragEnd(node),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({required this.graph, required this.posOf});
  final AdminLessonGraph graph;
  final Offset Function(AdminGraphNode) posOf;

  AdminGraphNode? _find(String id) => graph.nodes.cast<AdminGraphNode?>().firstWhere((n) => n!.id == id, orElse: () => null);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AdminColors.accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final edge in graph.edges) {
      final from = _find(edge.fromNodeId);
      final to = _find(edge.toNodeId);
      if (from == null || to == null) continue;
      final start = posOf(from) + const Offset(_nodeWidth, _nodeHeight / 2);
      final end = posOf(to) + const Offset(0, _nodeHeight / 2);
      final control1 = Offset(start.dx + 50, start.dy);
      final control2 = Offset(end.dx - 50, end.dy);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(control1.dx, control1.dy, control2.dx, control2.dy, end.dx, end.dy);
      canvas.drawPath(path, paint);
      _drawArrowHead(canvas, paint, end, (end - control2));
    }
  }

  void _drawArrowHead(Canvas canvas, Paint paint, Offset tip, Offset direction) {
    final angle = direction.direction;
    const arrowLength = 9.0;
    const arrowAngle = 0.5;
    final p1 = tip - Offset(arrowLength * math.cos(angle - arrowAngle), arrowLength * math.sin(angle - arrowAngle));
    final p2 = tip - Offset(arrowLength * math.cos(angle + arrowAngle), arrowLength * math.sin(angle + arrowAngle));
    final fill = Paint()..color = paint.color;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      fill,
    );
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) => true;
}

/// One draggable node card on the canvas.
class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.node,
    required this.number,
    required this.selected,
    required this.connecting,
    required this.onTap,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final AdminGraphNode node;
  // Position in the walk-through order (§ lesson graph follow-up,
  // 2026-09-03) — null only defensively (see _computeOrder), never in
  // practice once every node has been assigned one.
  final int? number;
  final bool selected;
  final bool connecting;
  final VoidCallback onTap;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    final style = _nodeStyle[node.type] ?? (label: node.type, icon: Icons.circle_outlined, color: AdminColors.textSecondary);
    return GestureDetector(
      onTap: onTap,
      onPanUpdate: (details) => onPanUpdate(details.delta),
      onPanEnd: (_) => onPanEnd(),
      child: SizedBox(
        width: _nodeWidth,
        height: _nodeHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: AdminColors.card,
              borderRadius: BorderRadius.circular(AdminMetrics.blockRadius),
              elevation: selected ? 3 : 1,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AdminMetrics.blockRadius),
                  border: Border.all(color: connecting ? AdminColors.accent : (selected ? style.color : AdminColors.border), width: selected || connecting ? 2 : 1),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(style.icon, size: 20, color: style.color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(style.label, style: AdminTypography.caption),
                          Text(node.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AdminTypography.body.copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (number != null)
              Positioned(
                left: -8,
                top: -8,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AdminColors.accent,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    '$number',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Side panel for the selected node — rename, delete, and the node's real
/// content editor (unchanged widgets, just pointed at this node).
class _NodeInspector extends ConsumerStatefulWidget {
  const _NodeInspector({
    required this.courseId,
    required this.lesson,
    required this.node,
    required this.languageId,
    required this.onClose,
    required this.onDelete,
    required this.onReload,
  });

  final String courseId;
  final AdminLesson lesson;
  final AdminGraphNode node;
  final String? languageId;
  final VoidCallback onClose;
  final VoidCallback onDelete;
  final VoidCallback onReload;

  @override
  ConsumerState<_NodeInspector> createState() => _NodeInspectorState();
}

class _NodeInspectorState extends ConsumerState<_NodeInspector> {
  late final _title = TextEditingController(text: widget.node.title);
  bool _busy = false;

  @override
  void didUpdateWidget(covariant _NodeInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) _title.text = widget.node.title;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _saveTitle() async {
    final title = _title.text.trim();
    if (title.isEmpty || title == widget.node.title) return;
    setState(() => _busy = true);
    try {
      await ref.read(builderRepositoryProvider).updateGraphNode(widget.courseId, widget.lesson.id, widget.node.id, title: title);
      widget.onReload();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось переименовать блок');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadMedia(List<int> bytes, String filename) async {
    setState(() => _busy = true);
    try {
      await ref.read(builderRepositoryProvider).uploadGraphNodeMedia(widget.courseId, widget.lesson.id, widget.node.id, bytes: bytes, filename: filename);
      widget.onReload();
      if (mounted) showSuccessSnack(context);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось загрузить файл');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeMedia() async {
    setState(() => _busy = true);
    try {
      await ref.read(builderRepositoryProvider).removeGraphNodeMedia(widget.courseId, widget.lesson.id, widget.node.id);
      widget.onReload();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось удалить файл');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final style = _nodeStyle[node.type] ?? (label: node.type, icon: Icons.circle_outlined, color: AdminColors.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(style.icon, size: 18, color: style.color),
            const SizedBox(width: 8),
            Text(style.label, style: AdminTypography.cardTitle),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: widget.onClose),
          ],
        ),
        const SizedBox(height: AdminMetrics.fieldGap),
        Row(
          children: [
            Expanded(
              child: TextField(controller: _title, decoration: adminInputDecoration(label: 'Название блока'), onSubmitted: (_) => _saveTitle()),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: _busy ? null : _saveTitle, style: AdminButtonStyles.text(), child: const Text('Сохранить')),
          ],
        ),
        const SizedBox(height: AdminMetrics.cardGap),
        Expanded(child: SingleChildScrollView(child: _content(node))),
        const SizedBox(height: AdminMetrics.cardGap),
        TextButton(onPressed: widget.onDelete, style: AdminButtonStyles.dangerText(), child: const Text('Удалить блок')),
      ],
    );
  }

  Widget _content(AdminGraphNode node) {
    switch (node.type) {
      case 'vocabulary':
        return VocabularyEditor(
          courseId: widget.courseId,
          lessonId: widget.lesson.id,
          words: widget.lesson.vocabulary,
          onChanged: widget.onReload,
        );
      case 'material':
        return MaterialBlockEditor(
          courseId: widget.courseId,
          lessonId: widget.lesson.id,
          lessonTitle: widget.lesson.title,
          languageId: widget.languageId,
          materialId: node.refId,
        );
      case 'video':
      case 'audio':
        return MediaEditor(
          kind: node.type,
          url: node.mediaUrl,
          libraryLoader: () => ref.read(builderRepositoryProvider).listMediaLibrary(node.type),
          onUpload: _uploadMedia,
          onRemove: _removeMedia,
          onReuse: _reuseMedia,
        );
      case 'minitest':
      case 'practice':
      case 'review':
        final block = widget.lesson.blocks.cast<AdminBlock?>().firstWhere((b) => b!.id == node.refId, orElse: () => null);
        if (block == null) return Text('Блок не найден', style: AdminTypography.caption);
        return BlockEditor(
          courseId: widget.courseId,
          lessonId: widget.lesson.id,
          block: block,
          index: 0,
          total: 1,
          onMove: (_) {},
          onChanged: widget.onReload,
          languageId: widget.languageId,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // Points this node at a file already used elsewhere in the (cross-lesson,
  // legacy-field) media library — same picker MediaEditor already offers
  // for the old per-lesson video/audio, now backed by the node's own
  // mediaUrl instead.
  Future<void> _reuseMedia(String url) async {
    setState(() => _busy = true);
    try {
      await ref.read(builderRepositoryProvider).reuseGraphNodeMedia(widget.courseId, widget.lesson.id, widget.node.id, url);
      widget.onReload();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось выбрать файл');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ignore: unused_import
