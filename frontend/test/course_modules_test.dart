import 'package:flutter_test/flutter_test.dart';
import 'package:payroha/features/admin/course_builder/domain/builder_domain.dart';
import 'package:payroha/features/lesson_runner/domain/lesson_graph.dart';

// § course modules, 2026-10-05: modules, lesson plan, «Фразы» step and
// steps waiting for the AI, as the backend sends them.
void main() {
  Map<String, dynamic> node(String id, String type, {bool pending = false, List<Map<String, dynamic>> phrases = const []}) => {
        'id': id,
        'type': type,
        'refId': null,
        'mediaUrl': null,
        'title': type,
        'posX': 0,
        'posY': 0,
        'phraseIds': [for (final p in phrases) p['id']],
        'phrases': phrases,
        'aiTask': pending ? 'Explain to be' : null,
        'aiPending': pending,
      };

  test('admin course reads modules, plans and waiting steps', () {
    final course = AdminCourse.fromJson({
      'id': 'c1',
      'title': 'English A1',
      'status': 'DRAFT',
      'position': 0,
      'modules': [
        {'id': 'm1', 'title': 'Знакомство', 'titleTg': 'Шиносоӣ', 'description': '', 'position': 0},
      ],
      'lessons': [
        {
          'id': 'l1',
          'title': 'Привет',
          'moduleId': 'm1',
          'planEn': 'Greetings',
          'planRu': 'Приветствия',
          'vocabulary': [],
          'blocks': [],
          'graph': {
            'nodes': [
              node('n1', 'phrases', phrases: [
                {'id': 'p1', 'text': 'Nice to meet you', 'translation': 'Приятно познакомиться'},
              ]),
              node('n2', 'material', pending: true),
              node('n3', 'minitest', pending: true),
            ],
            'edges': [],
          },
        },
      ],
    });
    expect(course.modules.single.titleTg, 'Шиносоӣ');
    final lesson = course.lessons.single;
    expect(lesson.moduleId, 'm1');
    expect(lesson.planEn, 'Greetings');
    expect(lesson.pendingSteps, 2);
    expect(lesson.graph!.nodes.first.phrases.single.text, 'Nice to meet you');
    expect(lesson.graph!.nodes[1].aiTask, 'Explain to be');
  });

  test('a course from before modules still parses', () {
    final course = AdminCourse.fromJson({'id': 'c', 'title': 't', 'status': 'DRAFT', 'position': 0, 'lessons': []});
    expect(course.modules, isEmpty);
  });

  test('learner phrases step carries translated phrases', () {
    final n = GraphNode.fromJson(node('n1', 'phrases', phrases: [
      {'id': 'p1', 'text': 'My name is Ali', 'translation': 'Номи ман Алӣ'},
    ]));
    expect(n.phrases.single.translation, 'Номи ман Алӣ');
    final old = GraphNode.fromJson({'id': 'x', 'type': 'vocabulary', 'refId': null, 'mediaUrl': null, 'title': 'Слова'});
    expect(old.phrases, isEmpty);
  });
}
