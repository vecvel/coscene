import 'dart:ui';

import 'package:coscene_core/coscene_core.dart';

/// What the player's finger just did, so the app can answer with a sound
/// and a tap of the motor.
enum SceneFeedback {
  /// A part clicked into a valid place.
  snap,

  /// A dial, mirror or valve moved one step.
  tick,

  /// The move was not allowed.
  reject,

  /// A part was picked up.
  lift,
}

/// The result of a submission being played back.
class Playback {
  const Playback(this.outcome, this.timeline);
  final Outcome outcome;
  final Timeline timeline;
}

/// Everything a delegate needs to draw one frame.
class PaintContext {
  const PaintContext({
    required this.playback,
    required this.time,
    required this.ghost,
    required this.clock,
    required this.reduceMotion,
  });

  /// Set after the player presses the action button, cleared on the next edit.
  final Playback? playback;

  /// Seconds into [playback].
  final double time;

  /// Snapshot of the last failed setup, or null. Draw it faintly.
  final Map<String, dynamic>? ghost;

  /// Seconds since the view appeared, for gentle idle motion.
  final double clock;
  final bool reduceMotion;

  bool get playing => playback != null;
  bool get finished => playback != null && time >= playback!.timeline.duration;
  Outcome? get outcome => playback?.outcome;

  /// Value of a playback track now, or [orElse] when nothing is playing.
  double track(String name, {double orElse = 0}) =>
      playback == null ? orElse : playback!.timeline.at(name, time, orElse: orElse);
}

/// Draws one archetype and turns touches into moves on its [Scene].
///
/// Coordinates are scene units inside [logicalSize]; the view handles
/// scaling. Call [changed] after every edit to the scene and [feedback]
/// whenever the player should feel or hear something.
abstract class SceneDelegate<S extends Scene> {
  SceneDelegate(this.scene);
  final S scene;

  Size get logicalSize => const Size(100, 100);

  void Function()? onChanged;
  void Function(SceneFeedback)? onFeedback;

  void changed() => onChanged?.call();
  void feedback(SceneFeedback f) => onFeedback?.call(f);

  /// Advances local easing. Return true while something is still moving.
  bool tick(double dt) => false;

  void paint(Canvas canvas, PaintContext ctx);

  /// Finger down. Return true to start a drag; false lets a tap through.
  bool onDown(Offset p) => false;
  void onMove(Offset p) {}
  void onUp(Offset p) {}

  /// A quick touch that did not turn into a drag.
  void onTap(Offset p) {}

  /// Called when the scene was reset or restored from outside.
  void sync() {}
}
