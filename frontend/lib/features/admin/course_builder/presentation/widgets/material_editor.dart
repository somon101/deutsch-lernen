import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/builder_repository.dart';
import '../../domain/builder_domain.dart';
import '../../../widgets/admin_feedback.dart';

/// Mirrors the material-text step shared by AdminLessonEditPage.tsx (legacy,
/// direct PUT /api/admin/content/:id) and BuilderLessonEditor.tsx (builder,
/// PATCH .../lessons/:id) — the save action itself is injected so this
/// widget doesn't need to know which endpoint it's hitting.
class MaterialEditor extends ConsumerStatefulWidget {
  const MaterialEditor({super.key, required this.materialText, required this.onSave});

  final String materialText;
  final Future<void> Function(String materialText) onSave;

  @override
  ConsumerState<MaterialEditor> createState() => _MaterialEditorState();
}

class _MaterialEditorState extends ConsumerState<MaterialEditor> {
  late final _controller = TextEditingController(text: widget.materialText);
  bool _busy = false;
  bool _searching = false;
  List<MaterialLibraryEntry>? _results;
  Timer? _debounce;
  final _query = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    _query.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.onSave(_controller.text);
      if (mounted) showSuccessSnack(context);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить материал');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _searching = true);
      final results = await ref.read(builderRepositoryProvider).searchMaterials(value.trim());
      if (mounted) {
        setState(() {
          _results = results;
          _searching = false;
        });
      }
    });
  }

  Future<void> _pick(MaterialLibraryEntry entry) async {
    if (_controller.text.trim().isNotEmpty) {
      final ok = await confirmDialog(context, title: 'Заменить текущий текст материала найденным?');
      if (!ok) return;
    }
    _controller.text = entry.materialText;
    setState(() {
      _results = null;
      _query.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _query,
          decoration: const InputDecoration(labelText: 'Найти материал в других уроках (только курсы конструктора)'),
          onChanged: _onQueryChanged,
        ),
        if (_searching) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
        if (_results != null && _results!.isNotEmpty)
          Card(
            child: Column(
              children: [
                for (final r in _results!)
                  ListTile(dense: true, title: Text(r.label), subtitle: Text(r.snippet), onTap: () => _pick(r)),
              ],
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          maxLines: 16,
          decoration: const InputDecoration(border: OutlineInputBorder(), alignLabelWithHint: true),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Сохраняем…' : 'Сохранить')),
        ),
      ],
    );
  }
}
