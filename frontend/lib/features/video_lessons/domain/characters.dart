import 'package:flutter/widgets.dart';

import '../presentation/cloud_character.dart';
import 'performance.dart';

/// A character the video constructor can animate: a rigged model that
/// renders any [CharacterPose] (skeleton + face rig + mouth shapes). The
/// performance (speech -> pose over time) is shared by all characters, so
/// adding one means adding its model here, not new animation logic.
class CharacterModel {
  const CharacterModel({required this.id, required this.name, required this.builder});
  final String id;
  final String name;
  final Widget Function(CharacterPose pose) builder;
}

final characterModels = <String, CharacterModel>{
  'cloud': CharacterModel(id: 'cloud', name: 'Облачко', builder: (pose) => CloudCharacter(pose: pose)),
};

CharacterModel characterFor(String id) => characterModels[id] ?? characterModels.values.first;
