import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/back_guard.dart';
import '../../../profile/presentation/profile_tokens.dart';
import '../../widgets/admin_feedback.dart';
import '../../course_builder/data/builder_repository.dart';
import '../../course_builder/domain/taxonomy_domain.dart';

final adminLanguagesProvider = FutureProvider.autoDispose<List<AdminLanguage>>(
  (ref) => ref.watch(builderRepositoryProvider).listLanguages(),
);

/// Entry point of the course constructor: one card per studied language.
/// Opening a card leads to that language's workspace (courses, dictionary,
/// phrases, rules). Colors follow the app's light/dark theme setting.
class AdminLanguagesScreen extends ConsumerWidget {
  const AdminLanguagesScreen({super.key});

  Future<void> _addLanguage(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(context: context, builder: (_) => const _NameDialog());
    if (name == null || name.trim().isEmpty) return;
    try {
      final (language, existing) = await ref.read(builderRepositoryProvider).createLanguage(name.trim());
      ref.invalidate(adminLanguagesProvider);
      if (context.mounted) {
        showSuccessSnack(context, existing ? 'Язык «${language.name}» уже есть' : 'Язык «${language.name}» добавлен');
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e, 'Не удалось добавить язык');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.profileColors;
    final languages = ref.watch(adminLanguagesProvider);
    return BackGuard(
      fallbackPath: '/',
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: c.bg,
          foregroundColor: c.text,
          elevation: 0,
          centerTitle: true,
          title: Text('Языки', style: TextStyle(color: c.text, fontWeight: FontWeight.w600, fontSize: 18)),
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 24 + bottomBarClearance(context)),
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Языки', style: TextStyle(color: c.text, fontSize: 28, fontWeight: FontWeight.w800))),
                    FilledButton(
                      onPressed: () => _addLanguage(context, ref),
                      style: FilledButton.styleFrom(
                        backgroundColor: c.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('+ Добавить язык', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                languages.when(
                  loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Text(adminErrorMessage(e, 'Не удалось загрузить языки'), style: TextStyle(color: c.danger)),
                  data: (list) => list.isEmpty
                      ? Text('Языков пока нет — добавьте первый.', style: TextStyle(color: c.textMuted))
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final twoColumns = constraints.maxWidth >= 700;
                            final cardWidth = twoColumns ? (constraints.maxWidth - 16) / 2 : constraints.maxWidth;
                            return Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [for (final l in list) SizedBox(width: cardWidth, child: _LanguageCard(language: l))],
                            );
                          },
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

class _LanguageCard extends ConsumerStatefulWidget {
  const _LanguageCard({required this.language});
  final AdminLanguage language;

  @override
  ConsumerState<_LanguageCard> createState() => _LanguageCardState();
}

class _LanguageCardState extends ConsumerState<_LanguageCard> {
  late final _alphabet = TextEditingController(text: widget.language.alphabet ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _alphabet.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String fallback, {String? success}) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(adminLanguagesProvider);
      if (mounted && success != null) showSuccessSnack(context, success);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, fallback);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAlphabet() => _run(
        () => ref.read(builderRepositoryProvider).updateLanguage(widget.language.id, alphabet: _alphabet.text.trim()),
        'Не удалось сохранить алфавит',
        success: 'Алфавит сохранён',
      );

  Future<void> _togglePublish() {
    final publish = !widget.language.isPublished;
    return _run(
      () => ref.read(builderRepositoryProvider).updateLanguage(widget.language.id, status: publish ? 'PUBLISHED' : 'DRAFT'),
      'Не удалось изменить статус',
      success: publish ? 'Язык опубликован' : 'Язык снят с публикации — ученики его не видят',
    );
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Удалить язык «${widget.language.name}»?',
      message: 'Удалить можно только пустой язык — без курсов, слов, фраз и правил.',
      confirmLabel: 'Удалить',
    );
    if (!ok) return;
    await _run(() => ref.read(builderRepositoryProvider).deleteLanguage(widget.language.id), 'Не удалось удалить язык', success: 'Язык удалён');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    final l = widget.language;
    final pillStyle = TextButton.styleFrom(
      backgroundColor: c.cardHover,
      foregroundColor: c.accent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontWeight: FontWeight.w600),
    );
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(24), border: Border.all(color: c.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.name, style: TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          SelectableText('ID: ${l.id}', style: TextStyle(color: c.textMuted, fontSize: 12)),
          const SizedBox(height: 10),
          Text.rich(TextSpan(children: [
            TextSpan(text: 'Статус: ', style: TextStyle(color: c.text, fontWeight: FontWeight.w600)),
            TextSpan(
              text: l.isPublished ? 'Опубликовано' : 'Черновик',
              style: TextStyle(color: l.isPublished ? c.success : c.warning, fontWeight: FontWeight.w700),
            ),
          ])),
          const SizedBox(height: 6),
          Text(
            '${l.wordCount} слов · ${l.phraseCount} фраз · ${l.ruleCount} правил · ${l.courseCount} курсов',
            style: TextStyle(color: c.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Text('Алфавит (для упражнений с буквами)', style: TextStyle(color: c.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _alphabet,
                  enabled: !_busy,
                  style: TextStyle(color: c.text),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: c.cardHover,
                    hintText: 'abcdefghijklmnopqrstuvwxyz',
                    hintStyle: TextStyle(color: c.textMuted),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: _busy ? null : _saveAlphabet, style: pillStyle, child: const Text('Сохранить')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(onPressed: () => context.go('/admin/languages/${Uri.encodeComponent(l.id)}'), style: pillStyle, child: const Text('Открыть')),
                    l.isPublished
                        ? TextButton(onPressed: _busy ? null : _togglePublish, style: pillStyle, child: const Text('Снять с публикации'))
                        : FilledButton(
                            onPressed: _busy ? null : _togglePublish,
                            style: FilledButton.styleFrom(
                              backgroundColor: c.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: const StadiumBorder(),
                              textStyle: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            child: const Text('Опубликовать'),
                          ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _delete,
                style: TextButton.styleFrom(foregroundColor: c.textMuted),
                child: const Text('Удалить'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новый язык'),
      content: TextField(
        controller: _name,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Название (например, English, 中文)'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, _name.text), child: const Text('Добавить')),
      ],
    );
  }
}
