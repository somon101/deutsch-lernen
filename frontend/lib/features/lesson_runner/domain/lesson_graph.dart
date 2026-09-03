import 'dart:collection';

import 'progress.dart';

/// Student-facing lesson graph (§ lesson graph, 2026-09-03) — a lightweight,
/// independent mirror of the admin's AdminGraphNode/AdminGraphEdge (kept
/// separate on purpose, same "richer admin DTO vs learner DTO" convention
/// features/admin/course_builder/domain/builder_domain.dart already
/// documents for every other piece of lesson content). A lesson with no
/// graph (`json['graph'] == null`, from services/courses.py's lesson_dto)
/// stays on the old fixed Stage-enum runner entirely — nothing here is used
/// for it.
class GraphNode {
  const GraphNode({required this.id, required this.type, required this.refId, required this.mediaUrl, required this.title});

  factory GraphNode.fromJson(Map<String, dynamic> json) => GraphNode(
        id: json['id'] as String,
        type: json['type'] as String,
        refId: json['refId'] as String?,
        mediaUrl: json['mediaUrl'] as String?,
        title: json['title'] as String,
      );

  final String id;
  // "vocabulary" | "material" | "video" | "audio" | "minitest" | "practice" | "review"
  final String type;
  final String? refId;
  final String? mediaUrl;
  final String title;
}

class GraphEdge {
  const GraphEdge({required this.fromNodeId, required this.toNodeId, required this.position});

  factory GraphEdge.fromJson(Map<String, dynamic> json) =>
      GraphEdge(fromNodeId: json['fromNodeId'] as String, toNodeId: json['toNodeId'] as String, position: json['position'] as int? ?? 0);

  final String fromNodeId;
  final String toNodeId;
  final int position;
}

class LessonGraph {
  const LessonGraph({required this.nodes, required this.edges});

  factory LessonGraph.fromJson(Map<String, dynamic> json) => LessonGraph(
        nodes: (json['nodes'] as List<dynamic>).map((n) => GraphNode.fromJson(n as Map<String, dynamic>)).toList(),
        edges: (json['edges'] as List<dynamic>).map((e) => GraphEdge.fromJson(e as Map<String, dynamic>)).toList(),
      );

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
}

/// Topologically sorts the graph into the one linear sequence every student
/// walks (Kahn's algorithm; a node's several outgoing edges are visited in
/// `position` order, so authoring stays a free graph while running stays a
/// single deterministic route — the "flattened linear path" decision for
/// this feature). A node the graph never reaches from a root (an accidental
/// island, or a cycle the builder's own add_edge already refuses to create)
/// is still appended at the end, in its original array order, rather than
/// silently dropped.
List<GraphNode> flattenGraph(LessonGraph graph) {
  final byId = {for (final n in graph.nodes) n.id: n};
  final indegree = {for (final n in graph.nodes) n.id: 0};
  final outEdges = <String, List<GraphEdge>>{};
  for (final e in graph.edges) {
    if (!byId.containsKey(e.fromNodeId) || !byId.containsKey(e.toNodeId)) continue;
    (outEdges[e.fromNodeId] ??= []).add(e);
    indegree[e.toNodeId] = (indegree[e.toNodeId] ?? 0) + 1;
  }
  for (final edges in outEdges.values) {
    edges.sort((a, b) => a.position.compareTo(b.position));
  }

  final remaining = Map<String, int>.from(indegree);
  final queue = Queue<String>();
  for (final n in graph.nodes) {
    if ((indegree[n.id] ?? 0) == 0) queue.add(n.id);
  }

  final visited = <String>{};
  final result = <GraphNode>[];
  while (queue.isNotEmpty) {
    final id = queue.removeFirst();
    if (!visited.add(id)) continue;
    result.add(byId[id]!);
    for (final e in outEdges[id] ?? const <GraphEdge>[]) {
      remaining[e.toNodeId] = (remaining[e.toNodeId] ?? 0) - 1;
      if (remaining[e.toNodeId] == 0) queue.add(e.toNodeId);
    }
  }
  for (final n in graph.nodes) {
    if (!visited.contains(n.id)) result.add(n);
  }
  return result;
}

bool isNodeUnlocked(List<GraphNode> flat, Set<String> completed, String nodeId) {
  final idx = flat.indexWhere((n) => n.id == nodeId);
  if (idx <= 0) return true;
  return completed.contains(flat[idx - 1].id);
}

/// Null means every node is done — the caller shows the results screen.
GraphNode? nextIncompleteNode(List<GraphNode> flat, Set<String> completed) {
  for (final n in flat) {
    if (!completed.contains(n.id)) return n;
  }
  return null;
}

double graphProgressRatio(List<GraphNode> flat, Set<String> completed) {
  if (flat.isEmpty) return 0;
  return completed.where((id) => flat.any((n) => n.id == id)).length / flat.length;
}

/// Mirrors LessonProgress (domain/progress.dart) for a graph lesson —
/// `Set<Stage>` there can't hold arbitrary node ids (LessonProgress.fromJson
/// drops anything that isn't one of the 8 fixed names), so a graph lesson
/// gets this parallel, string-keyed shape instead. Same wire endpoint
/// (PUT /api/me/lesson-state/:id) and same server-side row — only the
/// meaning of `completedStages` differs (node ids, not stage names) and
/// `nodeResults` is new (§ lesson graph, 2026-09-03).
class GraphLessonProgress {
  const GraphLessonProgress({
    required this.lessonId,
    required this.completedNodeIds,
    required this.vocabIndex,
    required this.nodeResults,
    required this.startedAt,
    this.completedAt,
  });

  factory GraphLessonProgress.empty(String lessonId) => GraphLessonProgress(
        lessonId: lessonId,
        completedNodeIds: const {},
        vocabIndex: 0,
        nodeResults: const {},
        startedAt: DateTime.now().toUtc().toIso8601String(),
      );

  factory GraphLessonProgress.fromJson(Map<String, dynamic> json) => GraphLessonProgress(
        lessonId: json['lessonId'] as String,
        completedNodeIds: (json['completedStages'] as List<dynamic>).cast<String>().toSet(),
        vocabIndex: json['vocabIndex'] as int? ?? 0,
        nodeResults: (json['nodeResults'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, QuizResult.fromJson(v as Map<String, dynamic>)),
            ) ??
            const {},
        startedAt: json['startedAt'] as String,
        completedAt: json['completedAt'] as String?,
      );

  final String lessonId;
  final Set<String> completedNodeIds;
  final int vocabIndex;
  final Map<String, QuizResult> nodeResults;
  final String startedAt;
  final String? completedAt;

  GraphLessonProgress copyWith({
    Set<String>? completedNodeIds,
    int? vocabIndex,
    Map<String, QuizResult>? nodeResults,
    String? completedAt,
  }) =>
      GraphLessonProgress(
        lessonId: lessonId,
        completedNodeIds: completedNodeIds ?? this.completedNodeIds,
        vocabIndex: vocabIndex ?? this.vocabIndex,
        nodeResults: nodeResults ?? this.nodeResults,
        startedAt: startedAt,
        completedAt: completedAt ?? this.completedAt,
      );

  Map<String, dynamic> toJson() => {
        'completedStages': completedNodeIds.toList(),
        'vocabIndex': vocabIndex,
        if (nodeResults.isNotEmpty) 'nodeResults': nodeResults.map((k, v) => MapEntry(k, v.toJson())),
        'startedAt': startedAt,
        if (completedAt != null) 'completedAt': completedAt,
      };
}
