import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/back_guard.dart';
import '../../admin_tokens.dart';
import '../../widgets/admin_feedback.dart';
import '../data/ai_repository.dart';

final _aiSettingsProvider = FutureProvider.autoDispose<AiSettings>((ref) => ref.watch(aiRepositoryProvider).getSettings());

/// Admin-only «ИИ» screen (§ AI lesson generator, 2026-10-03): where the
/// DeepSeek API key is pasted. The key is write-only — once saved the
/// server only reports that one is set and its last four characters.
class AdminAiSettingsScreen extends ConsumerStatefulWidget {
  const AdminAiSettingsScreen({super.key});

  @override
  ConsumerState<AdminAiSettingsScreen> createState() => _AdminAiSettingsScreenState();
}

class _AdminAiSettingsScreenState extends ConsumerState<AdminAiSettingsScreen> {
  final _keyController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String fallback, {String? success}) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(_aiSettingsProvider);
      if (mounted) showSuccessSnack(context, success ?? 'Сохранено');
    } catch (e) {
      if (mounted) showErrorSnack(context, e, fallback);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    await _run(() async {
      await ref.read(aiRepositoryProvider).saveKey(key);
      _keyController.clear();
    }, 'Не удалось сохранить ключ');
  }

  Future<void> _removeKey() async {
    final ok = await confirmDialog(context, title: 'Удалить ключ?', message: 'Генерация уроков с ИИ перестанет работать, пока не будет добавлен новый ключ.', confirmLabel: 'Удалить');
    if (!ok) return;
    await _run(() => ref.read(aiRepositoryProvider).saveKey(''), 'Не удалось удалить ключ', success: 'Ключ удалён');
  }

  Future<void> _test() => _run(() => ref.read(aiRepositoryProvider).testConnection(), 'Проверка не прошла', success: 'Подключение работает');

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(_aiSettingsProvider);
    return BackGuard(
      fallbackPath: '/',
      child: Theme(
        data: lightTheme,
        child: Scaffold(
          backgroundColor: AdminColors.bg,
          appBar: AppBar(
            backgroundColor: AdminColors.card,
            foregroundColor: AdminColors.text,
            elevation: 0,
            title: Text('Искусственный интеллект', style: AdminTypography.pageTitle),
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
          ),
          body: AdminMaxWidth(
            maxWidth: AdminMetrics.maxContentWidth,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                settings.maybeWhen(
                  data: (s) => s.availableModels.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: AdminCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Модель', style: AdminTypography.cardTitle),
                                const SizedBox(height: 4),
                                Text('Выбор влияет на все следующие генерации уроков. Меняется сразу после выбора.', style: AdminTypography.caption),
                                for (final option in s.availableModels)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    enabled: !_busy,
                                    onTap: option.id == s.model || _busy
                                        ? null
                                        : () => _run(
                                              () => ref.read(aiRepositoryProvider).saveModel(option.id),
                                              'Не удалось сменить модель',
                                              success: 'Модель: ${option.label}',
                                            ),
                                    leading: Icon(
                                      option.id == s.model ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                      color: option.id == s.model ? AdminColors.accent : AdminColors.text,
                                    ),
                                    title: Text(option.label, style: AdminTypography.body),
                                    subtitle: Text(option.description, style: AdminTypography.caption),
                                  ),
                              ],
                            ),
                          ),
                        ),
                  orElse: () => const SizedBox.shrink(),
                ),
                settings.maybeWhen(
                  data: (s) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _PromptCard(
                      key: ValueKey('${s.isCustomPrompt}:${s.systemPrompt.hashCode}'),
                      settings: s,
                      onSaved: () => ref.invalidate(_aiSettingsProvider),
                    ),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
                AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DeepSeek', style: AdminTypography.cardTitle),
                      const SizedBox(height: 4),
                      Text(
                        'ИИ создаёт уроки из слов Словаря и базы фраз. Ключ выдаётся на platform.deepseek.com → API keys. '
                        'Он хранится на сервере в зашифрованном виде и больше нигде не показывается.',
                        style: AdminTypography.caption,
                      ),
                      const SizedBox(height: AdminMetrics.fieldGap),
                      settings.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => Text(adminErrorMessage(e, 'Не удалось загрузить настройки'), style: AdminTypography.body),
                        data: (s) => Row(
                          children: [
                            Icon(s.hasKey ? Icons.check_circle : Icons.error_outline, size: 18, color: s.hasKey ? AdminColors.success : AdminColors.warn),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.hasKey ? 'Ключ сохранён: ••••${s.keyHint ?? ''}  ·  модель ${s.model}' : 'Ключ не задан — генерация уроков недоступна',
                                style: AdminTypography.body,
                              ),
                            ),
                            if (s.hasKey) ...[
                              TextButton(onPressed: _busy ? null : _test, style: AdminButtonStyles.text(), child: const Text('Проверить подключение')),
                              TextButton(onPressed: _busy ? null : _removeKey, style: AdminButtonStyles.dangerText(), child: const Text('Удалить ключ')),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AdminMetrics.fieldGap),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _keyController,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: adminInputDecoration(label: 'API-ключ DeepSeek', hint: 'sk-…'),
                              onSubmitted: (_) => _saveKey(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(onPressed: _busy ? null : _saveKey, style: AdminButtonStyles.primary(), child: const Text('Сохранить')),
                        ],
                      ),
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


/// The admin's own rules for how the model writes a lesson. The fixed
/// output-format tail (the JSON keys the server parses) is shown read-only
/// and always appended, so editing the rules can't break parsing.
class _PromptCard extends ConsumerStatefulWidget {
  const _PromptCard({super.key, required this.settings, required this.onSaved});
  final AiSettings settings;
  final VoidCallback onSaved;

  @override
  ConsumerState<_PromptCard> createState() => _PromptCardState();
}

class _PromptCardState extends ConsumerState<_PromptCard> {
  late final _text = TextEditingController(text: widget.settings.systemPrompt);
  bool _busy = false;
  bool _showFormat = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _dirty => _text.text.trim() != widget.settings.systemPrompt.trim();

  Future<void> _save(String value, String success) async {
    setState(() => _busy = true);
    try {
      await ref.read(aiRepositoryProvider).savePrompt(value);
      if (mounted) showSuccessSnack(context, success);
      widget.onSaved();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить промт');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final ok = await confirmDialog(
      context,
      title: 'Вернуть стандартный промт?',
      message: 'Ваш текст промта будет заменён встроенным.',
      confirmLabel: 'Вернуть',
    );
    if (ok) await _save('', 'Возвращён стандартный промт');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Промт генерации уроков', style: AdminTypography.cardTitle)),
              Text(s.isCustomPrompt ? 'свой' : 'стандартный', style: AdminTypography.caption),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Правила, по которым ИИ пишет урок: сколько блоков, какие вопросы, стиль объяснений и т.д. '
            'Слова, фразы, курс и ваши пожелания сервер добавляет сам. Применяется к следующим генерациям.',
            style: AdminTypography.caption,
          ),
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(
            controller: _text,
            enabled: !_busy,
            minLines: 10,
            maxLines: 30,
            style: AdminTypography.mono,
            onChanged: (_) => setState(() {}),
            decoration: adminInputDecoration(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy || !_dirty || _text.text.trim().isEmpty ? null : () => _save(_text.text, 'Промт сохранён'),
                style: AdminButtonStyles.primary(),
                child: const Text('Сохранить'),
              ),
              if (s.isCustomPrompt)
                OutlinedButton(onPressed: _busy ? null : _reset, style: AdminButtonStyles.secondary(), child: const Text('Вернуть стандартный')),
              TextButton(
                onPressed: () => setState(() => _showFormat = !_showFormat),
                style: AdminButtonStyles.text(),
                child: Text(_showFormat ? 'Скрыть формат ответа' : 'Показать формат ответа (не редактируется)'),
              ),
            ],
          ),
          if (_showFormat) ...[
            const SizedBox(height: 8),
            Text(
              'Эта часть всегда добавляется после вашего текста: сервер разбирает ответ ИИ именно по этим ключам.',
              style: AdminTypography.caption,
            ),
            const SizedBox(height: 6),
            SelectableText(s.outputFormatPrompt, style: AdminTypography.mono),
          ],
        ],
      ),
    );
  }
}
