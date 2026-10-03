import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../admin_tokens.dart';
import 'admin_feedback.dart';

/// "Загрузить файл .json" for the word and phrase import dialogs: reads the
/// chosen file as UTF-8 and hands its text over, so it lands in the same
/// text field a pasted list would and goes through the same validation.
class JsonFileButton extends StatelessWidget {
  const JsonFileButton({super.key, required this.onLoaded, this.enabled = true});

  final ValueChanged<String> onLoaded;
  final bool enabled;

  Future<void> _pick(BuildContext context) async {
    try {
      final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['json']);
      if (file == null) return;
      var text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      if (text.startsWith('﻿')) text = text.substring(1);
      onLoaded(text);
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e, 'Не удалось прочитать файл');
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? () => _pick(context) : null,
      style: AdminButtonStyles.secondary(),
      icon: const Icon(Icons.upload_file, size: 16),
      label: const Text('Загрузить файл .json'),
    );
  }
}
