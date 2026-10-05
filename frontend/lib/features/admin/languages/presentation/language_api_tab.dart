import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../../profile/presentation/profile_tokens.dart';
import '../../admin_tokens.dart';
import '../../admin_widgets.dart';
import '../../widgets/admin_feedback.dart';

class LanguageApiKey {
  const LanguageApiKey({
    required this.id,
    required this.name,
    required this.prefix,
    this.createdAt,
    this.lastUsedAt,
    this.permissions = const [],
    this.expiresAt,
    this.expired = false,
  });
  factory LanguageApiKey.fromJson(Map<String, dynamic> j) => LanguageApiKey(
        id: j['id'] as String,
        name: j['name'] as String,
        prefix: j['prefix'] as String,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
        lastUsedAt: DateTime.tryParse(j['lastUsedAt'] as String? ?? ''),
        permissions: [for (final p in (j['permissions'] as List?) ?? const []) p as String],
        expiresAt: DateTime.tryParse(j['expiresAt'] as String? ?? ''),
        expired: j['expired'] as bool? ?? false,
      );
  final String id;
  final String name;
  final String prefix;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
  final List<String> permissions;
  final DateTime? expiresAt;
  final bool expired;
}

// What a key may do (backend services/api_keys.py PERMISSIONS).
const _areas = {'words': 'Слова', 'phrases': 'Фразы', 'topics': 'Темы', 'courses': 'Курсы и уроки'};
const _actions = {'read': 'Чтение', 'write': 'Создание и изменение', 'delete': 'Удаление'};

String _permissionSummary(List<String> perms) {
  final parts = <String>[];
  for (final a in _areas.entries) {
    final acts = [for (final x in _actions.keys) if (perms.contains('${a.key}:$x')) x];
    if (acts.isEmpty) continue;
    final label = acts.contains('delete') ? 'всё' : (acts.contains('write') ? 'чтение и правка' : 'чтение');
    parts.add('${a.value}: $label');
  }
  return parts.isEmpty ? 'нет прав' : parts.join(' · ');
}

/// Name, permission checkboxes and expiry of a key — for a new key and for
/// editing one. Returns null on cancel.
Future<({String name, List<String> permissions, int? expiresInDays})?> _askKeySettings(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String name = '',
  List<String> permissions = const ['words:read', 'phrases:read', 'topics:read', 'courses:read'],
  bool editing = false,
}) {
  final nameCtrl = TextEditingController(text: name);
  final selected = {...permissions};
  // null = leave as is (editing) / no expiry (new); 0 = remove expiry.
  int? days = editing ? null : 0;
  return showDialog<({String name, List<String> permissions, int? expiresInDays})>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        void toggle(String perm, bool on) {
          setLocal(() {
            final area = perm.split(':').first;
            if (on) {
              selected.add(perm);
              if (!perm.endsWith(':read')) selected.add('$area:read');
            } else {
              selected.remove(perm);
              if (perm.endsWith(':read')) selected.removeWhere((p) => p.startsWith('$area:'));
            }
          });
        }

        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(controller: nameCtrl, autofocus: !editing, decoration: adminInputDecoration(label: 'Название (например, «Создание курса»)')),
                  const SizedBox(height: AdminMetrics.fieldGap),
                  Text('Что разрешено этому ключу', style: AdminTypography.fieldLabel),
                  const SizedBox(height: 4),
                  Table(
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    columnWidths: const {0: FlexColumnWidth(1.4)},
                    children: [
                      TableRow(children: [
                        const SizedBox.shrink(),
                        for (final a in _actions.values) Padding(padding: const EdgeInsets.all(4), child: Text(a, style: AdminTypography.caption, textAlign: TextAlign.center)),
                      ]),
                      for (final area in _areas.entries)
                        TableRow(children: [
                          Text(area.value, style: AdminTypography.body),
                          for (final act in _actions.keys)
                            Checkbox(
                              value: selected.contains('${area.key}:$act'),
                              onChanged: (v) => toggle('${area.key}:$act', v ?? false),
                            ),
                        ]),
                    ],
                  ),
                  Text(
                    'Ключ работает только в этом языке. Удаление выдавайте только при необходимости. '
                    'Опубликовать курс через API нельзя — это делает человек в конструкторе.',
                    style: AdminTypography.caption,
                  ),
                  const SizedBox(height: AdminMetrics.fieldGap),
                  DropdownButtonFormField<int?>(
                    initialValue: days,
                    decoration: adminInputDecoration(label: 'Срок действия'),
                    items: [
                      if (editing) const DropdownMenuItem<int?>(value: null, child: Text('Не менять')),
                      const DropdownMenuItem<int?>(value: 0, child: Text('Без срока')),
                      const DropdownMenuItem<int?>(value: 1, child: Text('1 день')),
                      const DropdownMenuItem<int?>(value: 7, child: Text('7 дней')),
                      const DropdownMenuItem<int?>(value: 30, child: Text('30 дней')),
                      const DropdownMenuItem<int?>(value: 365, child: Text('1 год')),
                    ],
                    onChanged: (v) => setLocal(() => days = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty || selected.isEmpty) return;
                Navigator.pop(ctx, (name: nameCtrl.text.trim(), permissions: selected.toList(), expiresInDays: days));
              },
              style: AdminButtonStyles.primary(),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    ),
  ).whenComplete(nameCtrl.dispose);
}

final _keysProvider = FutureProvider.autoDispose.family<List<LanguageApiKey>, String>((ref, languageId) async {
  final res = await ref.watch(apiClientProvider).get('/api/languages/${Uri.encodeComponent(languageId)}/api-keys');
  return [for (final k in (res['keys'] as List<dynamic>)) LanguageApiKey.fromJson(k as Map<String, dynamic>)];
});

String _date(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
}

/// «API» tab of a language workspace: keys for external programs that may
/// read and edit this language's words, phrases and rules, plus a short
/// reference of the endpoints (backend routers/public_api.py).
class LanguageApiTab extends ConsumerWidget {
  const LanguageApiTab({super.key, required this.languageId});
  final String languageId;

  Future<void> _edit(BuildContext context, WidgetRef ref, LanguageApiKey key) async {
    final settings = await _askKeySettings(context, title: 'Ключ «${key.name}»', confirmLabel: 'Сохранить', name: key.name, permissions: key.permissions, editing: true);
    if (settings == null) return;
    try {
      await ref.read(apiClientProvider).patch('/api/languages/${Uri.encodeComponent(languageId)}/api-keys/${key.id}', body: {
        'name': settings.name,
        'permissions': settings.permissions,
        'expiresInDays': ?settings.expiresInDays,
      });
      ref.invalidate(_keysProvider(languageId));
      if (context.mounted) showSuccessSnack(context, 'Права ключа сохранены');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e, 'Не удалось сохранить ключ');
    }
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final settings = await _askKeySettings(context, title: 'Новый API-ключ', confirmLabel: 'Создать');
    if (settings == null) return;
    try {
      final res = await ref.read(apiClientProvider).post('/api/languages/${Uri.encodeComponent(languageId)}/api-keys', body: {
        'name': settings.name,
        'permissions': settings.permissions,
        if ((settings.expiresInDays ?? 0) > 0) 'expiresInDays': settings.expiresInDays,
      });
      final key = (res['key'] as Map<String, dynamic>)['key'] as String;
      ref.invalidate(_keysProvider(languageId));
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ключ создан'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Скопируйте ключ сейчас — больше он показан не будет.', style: AdminTypography.body),
                const SizedBox(height: 12),
                SelectableText(key, style: AdminTypography.mono),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: key));
                showSuccessSnack(ctx, 'Ключ скопирован');
              },
              child: const Text('Копировать'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), style: AdminButtonStyles.primary(), child: const Text('Готово')),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e, 'Не удалось создать ключ');
    }
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref, LanguageApiKey key) async {
    final ok = await confirmDialog(
      context,
      title: 'Отозвать ключ «${key.name}»?',
      message: 'Программа с этим ключом сразу потеряет доступ.',
      confirmLabel: 'Отозвать',
    );
    if (!ok) return;
    try {
      await ref.read(apiClientProvider).delete('/api/languages/${Uri.encodeComponent(languageId)}/api-keys/${key.id}');
      ref.invalidate(_keysProvider(languageId));
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e, 'Не удалось отозвать ключ');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = ref.watch(_keysProvider(languageId));
    final base = '$apiBaseUrl/api/v1';
    return AdminMaxWidth(
      maxWidth: AdminMetrics.maxListWidth,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, AdminMetrics.cardGap, 16, AdminMetrics.cardGap + bottomBarClearance(context)),
        children: [
          AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('API-ключи', style: AdminTypography.cardTitle)),
                    FilledButton.icon(
                      onPressed: () => _create(context, ref),
                      style: AdminButtonStyles.primary(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Новый ключ'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Ключ даёт внешней программе доступ только к этому языку и только к тому, что вы разрешили: '
                  'слова, фразы, темы, курсы и уроки — отдельно чтение, правка и удаление. '
                  'Права и срок можно поменять в любой момент. К пользователям доступа нет.',
                  style: AdminTypography.caption,
                ),
                const SizedBox(height: AdminMetrics.fieldGap),
                keys.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text(adminErrorMessage(e, 'Не удалось загрузить ключи'), style: AdminTypography.body),
                  data: (list) => list.isEmpty
                      ? Text('Ключей пока нет.', style: AdminTypography.body)
                      : Column(
                          children: [
                            for (final k in list)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.key_outlined),
                                title: Text(k.name, style: AdminTypography.body),
                                subtitle: Text(
                                  '${k.prefix}…  ·  создан ${_date(k.createdAt)}  ·  последний запрос ${_date(k.lastUsedAt)}\n'
                                  '${_permissionSummary(k.permissions)}\n'
                                  '${k.expired ? 'СРОК ИСТЁК ${_date(k.expiresAt)}' : (k.expiresAt != null ? 'действует до ${_date(k.expiresAt)}' : 'без срока')}',
                                  style: AdminTypography.caption.copyWith(color: k.expired ? AdminColors.danger : null),
                                ),
                                isThreeLine: true,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(onPressed: () => _edit(context, ref, k), style: AdminButtonStyles.text(), child: const Text('Права')),
                                    AdminDeleteLink(onPressed: () => _revoke(context, ref, k), label: 'Отозвать'),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AdminMetrics.cardGap),
          AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Как пользоваться', style: AdminTypography.cardTitle),
                const SizedBox(height: 8),
                Text('Адрес и заголовок для каждого запроса:', style: AdminTypography.body),
                const SizedBox(height: 6),
                SelectableText('$base\nX-API-Key: <ваш ключ>', style: AdminTypography.mono),
                const SizedBox(height: AdminMetrics.fieldGap),
                SelectableText(
                  'GET    /words?q=&limit=100&offset=0     список слов\n'
                  'GET    /words/{id}                       одно слово\n'
                  'POST   /words                            {"word","translation","translation_tg","transcription?","category?"}\n'
                  'PATCH  /words/{id}                       любые из этих полей\n'
                  'DELETE /words/{id}?force=true            удалить (force — даже если слово уже в уроках)\n'
                  'POST   /words/import                     {"words":[{"original","translation","translation_tg"}]}\n'
                  '\n'
                  'GET    /phrases  ·  /phrases/{id}\n'
                  'POST   /phrases                          {"text","translation","translation_tg","topic?"}\n'
                  'PATCH  /phrases/{id}  ·  DELETE /phrases/{id}\n'
                  'POST   /phrases/import                   {"phrases":[{"text","translation","translation_tg"}]}\n'
                  '\n'
                  'GET    /topics  ·  /topics/{id}\n'
                  'POST   /topics                           {"name"}\n'
                  'PATCH  /topics/{id}  ·  DELETE /topics/{id}\n'
                  'POST   /topics/import                    {"topics":[{"name"}]}\n'
                  '\n'
                  'GET    /language                         проверить ключ: язык, права, срок\n'
                  '\n'
                  'Курсы (права «Курсы и уроки»):\n'
                  'GET    /levels                           уровни языка\n'
                  'GET    /courses  ·  /courses/{id}        курсы / весь курс: модули, уроки, слова, шаги, маршрут\n'
                  'POST   /courses                          {"title","title_tg?","description?","levelId"} — всегда черновик\n'
                  'PATCH  /courses/{id}  ·  DELETE /courses/{id}\n'
                  'POST   /courses/{id}/modules             {"title","title_tg?"}\n'
                  'PUT    /courses/{id}/modules/order       {"ids":[...]}\n'
                  'PATCH  /modules/{id}  ·  DELETE /modules/{id}\n'
                  'POST   /courses/{id}/lessons             {"title","title_tg?","moduleId?","planEn?","planRu?"}\n'
                  'GET    /lessons/{id}  ·  PATCH /lessons/{id}  ·  DELETE /lessons/{id}\n'
                  'POST   /lessons/{id}/words               {"wordIds":[...]} — слова из словаря\n'
                  'DELETE /lessons/{id}/words/{wordId}\n'
                  'POST   /lessons/{id}/steps               {"type","title?","aiTask?","aiPending?","phraseIds?"}\n'
                  'PATCH  /steps/{id}  ·  DELETE /steps/{id}\n'
                  'PUT    /lessons/{id}/route               {"stepIds":[...]} — порядок шагов для ученика',
                  style: AdminTypography.mono,
                ),
                const SizedBox(height: AdminMetrics.fieldGap),
                Text('Пример:', style: AdminTypography.body),
                const SizedBox(height: 6),
                SelectableText(
                  'curl -H "X-API-Key: pk_..." "$base/words?q=Tisch"',
                  style: AdminTypography.mono,
                ),
                const SizedBox(height: 8),
                Text(
                  'Ошибки приходят как {"error": "..."}: 401 — нет, неверный или просроченный ключ, 403 — у ключа нет такого права, '
                  '404 — нет такой записи в этом языке, 409 — дубликат или запись уже используется.',
                  style: AdminTypography.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
