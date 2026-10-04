import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../../profile/presentation/profile_tokens.dart';
import '../../admin_tokens.dart';
import '../../admin_widgets.dart';
import '../../widgets/admin_feedback.dart';

class LanguageApiKey {
  const LanguageApiKey({required this.id, required this.name, required this.prefix, this.createdAt, this.lastUsedAt});
  factory LanguageApiKey.fromJson(Map<String, dynamic> j) => LanguageApiKey(
        id: j['id'] as String,
        name: j['name'] as String,
        prefix: j['prefix'] as String,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
        lastUsedAt: DateTime.tryParse(j['lastUsedAt'] as String? ?? ''),
      );
  final String id;
  final String name;
  final String prefix;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
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

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый API-ключ'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: adminInputDecoration(label: 'Название (например, «Моя программа словаря»)'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), style: AdminButtonStyles.primary(), child: const Text('Создать')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    try {
      final res = await ref.read(apiClientProvider).post('/api/languages/${Uri.encodeComponent(languageId)}/api-keys', body: {'name': name.trim()});
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
                  'Ключ даёт внешней программе доступ на чтение, добавление, изменение и удаление слов, фраз и правил '
                  'только этого языка. К курсам и пользователям доступа нет.',
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
                                  '${k.prefix}…  ·  создан ${_date(k.createdAt)}  ·  последний запрос ${_date(k.lastUsedAt)}',
                                  style: AdminTypography.caption,
                                ),
                                trailing: AdminDeleteLink(onPressed: () => _revoke(context, ref, k), label: 'Отозвать'),
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
                  'GET    /rules  ·  /rules/{id}\n'
                  'POST   /rules                            {"text"}\n'
                  'PATCH  /rules/{id}  ·  DELETE /rules/{id}\n'
                  'POST   /rules/import                     {"rules":[{"text"}]}\n'
                  '\n'
                  'GET    /language                         проверить ключ: к какому языку он относится',
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
                  'Ошибки приходят как {"error": "..."}: 401 — нет или неверный ключ, 404 — нет такой записи в этом языке, '
                  '409 — дубликат или слово уже используется.',
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
