import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../admin_tokens.dart';
import '../../../widgets/admin_feedback.dart';
import '../../data/builder_repository.dart';
import '../../domain/builder_domain.dart';
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

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final selected = _selectedNodeId == null ? null : _graph.nodes.cast<AdminGraphNode?>().firstWhere((n) => n!.id == _selectedNodeId, orElse: () => null);

    final canvas = _GraphCanvas(
      graph: _graph,
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

    final toolbar = _GraphToolbar(
      busy: _busy,
      connecting: _connectFromId != null,
      onAdd: _addNode,
      onToggleConnect: () => setState(() => _connectFromId = _connectFromId == null ? (_selectedNodeId ?? '') : null),
    );

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

    if (!isWide) {
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: body),
        if (selected != null) ...[
          const SizedBox(width: AdminMetrics.cardGap),
          SizedBox(
            width: 380,
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
  const _GraphToolbar({required this.busy, required this.connecting, required this.onAdd, required this.onToggleConnect});
  final bool busy;
  final bool connecting;
  final ValueChanged<String> onAdd;
  final VoidCallback onToggleConnect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
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
    required this.posOf,
    required this.connectFromId,
    required this.selectedNodeId,
    required this.onNodeTap,
    required this.onNodeDragUpdate,
    required this.onNodeDragEnd,
  });

  final AdminLessonGraph graph;
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
    required this.selected,
    required this.connecting,
    required this.onTap,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final AdminGraphNode node;
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
        child: Material(
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
