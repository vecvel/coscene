import 'dart:typed_data';

import 'level_spec.dart';

/// The verdict on one submission.
class Outcome {
  const Outcome.solved([this.detail = const {}]) : success = true, kind = 'solved', magnitude = 0;

  const Outcome.failed(this.kind, {this.magnitude = 0, this.detail = const {}}) : success = false;

  final bool success;

  /// `solved`, or the way it went wrong (for example `tips_left`). The app
  /// shows `fail.<archetype>.<kind>` from the dictionary.
  final String kind;

  /// How far off the setup was, in the puzzle's own units. Drives how hard
  /// the failure plays out.
  final double magnitude;

  /// Extra numbers the renderer needs to play the result back.
  final Map<String, dynamic> detail;
}

/// A fixed-step recording of what happens after the player presses the
/// action button. Every track holds one value per frame.
class Timeline {
  Timeline(this.frames, Map<String, Float64List> tracks) : _tracks = tracks;

  /// Seconds per frame of the simulation.
  static const double dt = 1 / 60;

  final int frames;
  final Map<String, Float64List> _tracks;

  double get duration => frames * dt;
  Iterable<String> get trackNames => _tracks.keys;
  bool has(String track) => _tracks.containsKey(track);

  /// Value of [track] at [seconds], linearly interpolated between frames.
  double at(String track, double seconds, {double orElse = 0}) {
    final data = _tracks[track];
    if (data == null || data.isEmpty) return orElse;
    final f = seconds / dt;
    if (f <= 0) return data.first;
    if (f >= data.length - 1) return data.last;
    final i = f.floor();
    final frac = f - i;
    return data[i] + (data[i + 1] - data[i]) * frac;
  }

  double last(String track, {double orElse = 0}) {
    final data = _tracks[track];
    return data == null || data.isEmpty ? orElse : data.last;
  }
}

/// Builds timelines one frame at a time.
class TimelineBuilder {
  TimelineBuilder(this.frames);
  final int frames;
  final Map<String, Float64List> _tracks = {};

  Float64List track(String name) => _tracks.putIfAbsent(name, () => Float64List(frames));

  /// Fills a track from a function of the frame number.
  void fill(String name, double Function(int frame) value) {
    final data = track(name);
    for (var i = 0; i < frames; i++) {
      data[i] = value(i);
    }
  }

  /// Integrates a damped spring toward [target], starting at [start].
  void spring(
    String name, {
    required double target,
    double start = 0,
    double velocity = 0,
    double omega = 9,
    double damping = 0.28,
    int delay = 0,
  }) {
    final data = track(name);
    var x = start;
    var v = velocity;
    for (var i = 0; i < frames; i++) {
      if (i >= delay) {
        final a = omega * omega * (target - x) - 2 * damping * omega * v;
        v += a * Timeline.dt;
        x += v * Timeline.dt;
      }
      data[i] = x;
    }
  }

  /// Smooth ramp from 0 to 1 between two frames.
  void ramp(String name, int from, int to) {
    fill(name, (i) {
      if (i <= from) return 0;
      if (i >= to) return 1;
      final t = (i - from) / (to - from);
      return t * t * (3 - 2 * t);
    });
  }

  Timeline build() => Timeline(frames, _tracks);
}

class SimResult {
  const SimResult(this.outcome, this.timeline);
  final Outcome outcome;
  final Timeline timeline;
}

/// The live, mutable state of one level while it is being played.
abstract class Scene {
  Scene(this.level);
  final LevelSpec level;

  String get archetypeId => level.archetypeId;

  /// Puts every movable part back where the level started.
  void reset();

  /// A JSON-safe copy of the movable parts, for ghosts and saved games.
  Map<String, dynamic> snapshot();

  /// Applies a snapshot made by [snapshot]. Invalid snapshots throw.
  void restore(Map<String, dynamic> snapshot);

  /// Judges the current setup. Pure and deterministic.
  Outcome evaluate();

  /// Judges the setup and records how it plays out.
  SimResult simulate();
}

/// A setup that passes [Scene.evaluate], found by a solver.
class Solution {
  const Solution(this.state, {this.effort = 1, this.moves = const []});

  /// Snapshot that can be passed to [Scene.restore].
  final Map<String, dynamic> state;

  /// Rough count of deliberate steps needed, used to grade difficulty.
  final int effort;

  /// For puzzles where the route matters, the moves that lead to [state].
  final List<List<int>> moves;
}

/// One interaction pattern: how its levels are read, judged and solved.
abstract class Archetype {
  const Archetype();

  String get id;

  /// Builds the playable scene. Throws [LevelFormatException] on bad data.
  Scene create(LevelSpec level);

  /// Finds a winning setup, or null when the level cannot be solved.
  Solution? solve(LevelSpec level);

  /// Share of all possible setups that win, or null when it cannot be
  /// counted. Used to reject levels that random fiddling would solve.
  double? winFraction(LevelSpec level);
}

/// A dial or slider that moves in equal steps between two ends.
class Adjustable {
  Adjustable({required this.min, required this.max, required this.step, required double value})
    : index = ((value - min) / (step == 0 ? 1 : step)).round(),
      initialIndex = ((value - min) / (step == 0 ? 1 : step)).round();

  factory Adjustable.fromJson(JsonReader r) {
    final min = r.number('min');
    final max = r.number('max');
    final step = r.number('step', orElse: 1);
    final value = r.number('value');
    if (max < min || step <= 0) {
      throw LevelFormatException('"${r.path}" needs min <= max and step > 0', levelId: r.levelId);
    }
    final a = Adjustable(min: min, max: max, step: step, value: value);
    if (a.index < 0 || a.index >= a.count || (a.value - value).abs() > 1e-6) {
      throw LevelFormatException('"${r.path}value" is not on the step grid', levelId: r.levelId);
    }
    return a;
  }

  factory Adjustable.fixed(double value) => Adjustable(min: value, max: value, step: 1, value: value);

  final double min;
  final double max;
  final double step;
  final int initialIndex;
  int index;

  int get count => ((max - min) / step + 1e-9).floor() + 1;
  bool get isFixed => count <= 1;
  double get value => min + index * step;
  double valueAt(int i) => min + i * step;

  /// Moves to the step nearest to [v]. Returns true when the step changed.
  bool moveTo(double v) {
    final next = ((v - min) / step).round().clamp(0, count - 1);
    if (next == index) return false;
    index = next;
    return true;
  }

  void reset() => index = initialIndex;

  Map<String, dynamic> toJson() => {'min': min, 'max': max, 'step': step, 'value': value};
}
