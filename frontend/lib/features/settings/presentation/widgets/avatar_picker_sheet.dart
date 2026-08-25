import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../core/utils/image_crop.dart';
import '../../../profile/presentation/profile_tokens.dart';

/// Bottom sheet for changing/removing the avatar, reachable straight from
/// the settings screen (not just from Personal Details). Camera capture
/// only shows on Android — image_picker has no Windows desktop
/// implementation, so desktop stays on file_picker (already used
/// elsewhere in the app) for gallery/file selection. Every picked image is
/// center-cropped to a square before `onPicked` is called.
Future<void> showAvatarPickerSheet(
  BuildContext context, {
  required bool hasAvatar,
  required Future<void> Function(Uint8List bytes, String filename) onPicked,
  required Future<void> Function() onRemove,
}) {
  final l10n = AppLocalizations.of(context);
  final supportsCamera = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final c = sheetContext.profileColors;

      Future<void> pickFromGallery() async {
        Navigator.of(sheetContext).pop();
        final file = await FilePicker.pickFile(type: FileType.image);
        if (file == null) return;
        final bytes = await file.readAsBytes();
        await onPicked(cropToSquareCenter(bytes), 'avatar.jpg');
      }

      Future<void> pickFromCamera() async {
        Navigator.of(sheetContext).pop();
        final photo = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90);
        if (photo == null) return;
        final bytes = await photo.readAsBytes();
        await onPicked(cropToSquareCenter(bytes), 'avatar.jpg');
      }

      Future<void> remove() async {
        Navigator.of(sheetContext).pop();
        await onRemove();
      }

      return SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(ProfileMetrics.cardRadius),
            border: Border.all(color: c.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              if (supportsCamera)
                ListTile(
                  leading: Icon(Icons.photo_camera_outlined, color: c.text),
                  title: Text(l10n.avatarTakePhoto, style: ProfileTypography.body(sheetContext)),
                  onTap: pickFromCamera,
                ),
              ListTile(
                leading: Icon(Icons.photo_library_outlined, color: c.text),
                title: Text(l10n.avatarChooseFromGallery, style: ProfileTypography.body(sheetContext)),
                onTap: pickFromGallery,
              ),
              if (hasAvatar)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: c.danger),
                  title: Text(l10n.avatarRemovePhoto, style: ProfileTypography.body(sheetContext).copyWith(color: c.danger)),
                  onTap: remove,
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}
