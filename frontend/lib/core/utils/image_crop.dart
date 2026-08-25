import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Centers a square crop over a picked avatar image — pure-Dart (the
/// `image` package has no native platform code), so it behaves identically
/// on Android and Windows, unlike an interactive native crop UI which only
/// exists on mobile.
Uint8List cropToSquareCenter(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  final side = decoded.width < decoded.height ? decoded.width : decoded.height;
  final x = (decoded.width - side) ~/ 2;
  final y = (decoded.height - side) ~/ 2;
  final cropped = img.copyCrop(decoded, x: x, y: y, width: side, height: side);
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 90));
}
