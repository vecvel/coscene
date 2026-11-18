import 'package:coscene_core/coscene_core.dart';

import 'delegates/answer_delegate.dart';
import 'delegates/ops_delegate.dart';
import 'delegates/pick_delegate.dart';
import 'delegates/probe_delegate.dart';
import 'delegates/route_delegate.dart';
import 'scene_delegate.dart';

/// The painter and input handler for a scene's archetype.
SceneDelegate delegateFor(Scene scene) => switch (scene) {
  AnswerScene s => AnswerDelegate(s),
  ProbeScene s => ProbeDelegate(s),
  PickScene s => PickDelegate(s),
  OpsScene s => OpsDelegate(s),
  RouteScene s => RouteDelegate(s),
  _ => throw ArgumentError('no painter for ${scene.archetypeId}'),
};
