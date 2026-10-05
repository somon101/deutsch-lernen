import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A character the video constructor can animate. Each one is an asset
/// folder (`assets/characters/<id>/`) with a body image whose drawn mouth was
/// removed, and a character.json with the mouth/eye anchors as fractions
/// of the image — so new characters are added as data, not code.
class CharacterDefinition {
  const CharacterDefinition({
    required this.id,
    required this.name,
    required this.image,
    required this.aspect,
    required this.mouth,
    required this.eyes,
  });

  factory CharacterDefinition.fromJson(Map<String, dynamic> j) => CharacterDefinition(
        id: j['id'] as String,
        name: j['name'] as String,
        image: j['image'] as String,
        aspect: (j['aspect'] as num).toDouble(),
        mouth: MouthSpec.fromJson(j['mouth'] as Map<String, dynamic>),
        eyes: [for (final e in (j['eyes'] as List<dynamic>)) EyeSpec.fromJson(e as Map<String, dynamic>)],
      );

  final String id;
  final String name;
  final String image;
  /// width / height of the body image.
  final double aspect;
  final MouthSpec mouth;
  final List<EyeSpec> eyes;
}

class MouthSpec {
  const MouthSpec({required this.cx, required this.cy, required this.width, required this.height, required this.color, required this.inner, required this.tongue});
  factory MouthSpec.fromJson(Map<String, dynamic> j) => MouthSpec(
        cx: (j['cx'] as num).toDouble(),
        cy: (j['cy'] as num).toDouble(),
        width: (j['width'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
        color: _hex(j['color'] as String),
        inner: _hex(j['inner'] as String),
        tongue: _hex(j['tongue'] as String),
      );
  final double cx, cy, width, height;
  final Color color, inner, tongue;
}

class EyeSpec {
  const EyeSpec({required this.cx, required this.cy, required this.rx, required this.ry, required this.lidColor});
  factory EyeSpec.fromJson(Map<String, dynamic> j) => EyeSpec(
        cx: (j['cx'] as num).toDouble(),
        cy: (j['cy'] as num).toDouble(),
        rx: (j['rx'] as num).toDouble(),
        ry: (j['ry'] as num).toDouble(),
        lidColor: _hex(j['lidColor'] as String),
      );
  final double cx, cy, rx, ry;
  final Color lidColor;
}

Color _hex(String s) => Color(int.parse('FF${s.replaceFirst('#', '')}', radix: 16));

/// Registered characters. One today; adding another is a new asset folder
/// plus its id here.
const characterIds = ['cloud'];

final characterProvider = FutureProvider.family<CharacterDefinition, String>((ref, id) async {
  final safe = characterIds.contains(id) ? id : characterIds.first;
  final raw = await rootBundle.loadString('assets/characters/$safe/character.json');
  return CharacterDefinition.fromJson(jsonDecode(raw) as Map<String, dynamic>);
});
