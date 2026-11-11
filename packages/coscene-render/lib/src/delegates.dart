import 'package:coscene_core/coscene_core.dart';

import 'delegates/balance_delegate.dart';
import 'delegates/cargo_delegate.dart';
import 'delegates/flow_delegate.dart';
import 'delegates/gear_delegate.dart';
import 'delegates/lock_delegate.dart';
import 'delegates/ray_delegate.dart';
import 'delegates/routing_delegate.dart';
import 'delegates/shadow_delegate.dart';
import 'scene_delegate.dart';

/// The painter and input handler for a scene's archetype.
SceneDelegate delegateFor(Scene scene) => switch (scene) {
  BalanceScene s => BalanceDelegate(s),
  RayScene s => RayDelegate(s),
  ShadowScene s => ShadowDelegate(s),
  FlowScene s => FlowDelegate(s),
  RoutingScene s => RoutingDelegate(s),
  LockScene s => LockDelegate(s),
  GearScene s => GearDelegate(s),
  CargoScene s => CargoDelegate(s),
  _ => throw ArgumentError('no painter for ${scene.archetypeId}'),
};
