import '../level_spec.dart';
import '../scene.dart';
import '../vec2.dart';

/// A flat mirror that pivots about its middle in equal steps.
class RayMirror {
  RayMirror(this.center, this.length, this.stepDegrees, this.step, {required this.fixed}) : initialStep = step;
  final Vec2 center;
  final double length;
  final double stepDegrees;
  final bool fixed;
  final int initialStep;
  int step;

  /// A mirror looks the same after half a turn.
  int get steps => (180 / stepDegrees).round();
  double get degrees => step * stepDegrees;

  Segment get segment {
    final half = Vec2.fromDegrees(degrees, length / 2);
    return Segment(center - half, center + half);
  }
}

/// The route a beam takes through the scene.
class RayTrace {
  RayTrace(this.points, this.hit, this.bounces, this.miss);
  final List<Vec2> points;
  final bool hit;
  final int bounces;

  /// Gap between the beam and the edge of the sensor at its closest pass.
  final double miss;

  double get length {
    var l = 0.0;
    for (var i = 1; i < points.length; i++) {
      l += points[i].distanceTo(points[i - 1]);
    }
    return l;
  }
}

/// A lamp, pivoting mirrors, walls and a sensor inside a square room.
class RayScene extends Scene {
  RayScene(super.level) {
    final s = JsonReader(level.initialState, level.id, 'initialState.');
    final rules = JsonReader(level.validationRules, level.id, 'validationRules.');
    size = s.number('size', orElse: 100);
    final e = s.object('emitter');
    emitter = Vec2(e.number('x'), e.number('y'));
    emitterDegrees = e.number('degrees');
    final t = s.object('target');
    target = Vec2(t.number('x'), t.number('y'));
    targetRadius = rules.number('hitTolerance', orElse: t.number('radius', orElse: 4));
    minBounces = rules.integer('minBounces', orElse: 0);
    maxBounces = rules.integer('maxBounces', orElse: 12);
    for (final m in s.objects('mirrors')) {
      final stepDegrees = m.number('stepDegrees', orElse: 15);
      final degrees = m.number('degrees');
      final step = (degrees / stepDegrees).round();
      if ((step * stepDegrees - degrees).abs() > 1e-6 || 180 % stepDegrees != 0) {
        throw LevelFormatException('mirror angle is not on its step grid', levelId: level.id);
      }
      final mirror = RayMirror(
        Vec2(m.number('x'), m.number('y')),
        m.number('length'),
        stepDegrees,
        step % (180 / stepDegrees).round(),
        fixed: m.boolean('fixed', orElse: false),
      );
      mirrors.add(mirror);
    }
    for (final w in s.objects('walls', optional: true)) {
      walls.add(Segment(Vec2(w.number('x1'), w.number('y1')), Vec2(w.number('x2'), w.number('y2'))));
    }
    if (!mirrors.any((m) => !m.fixed)) {
      throw LevelFormatException('needs at least one mirror that turns', levelId: level.id);
    }
    bool inside(Vec2 p) => p.x >= 0 && p.x <= size && p.y >= 0 && p.y <= size;
    if (!inside(emitter) || !inside(target) || mirrors.any((m) => !inside(m.center))) {
      throw LevelFormatException('everything must sit inside the room', levelId: level.id);
    }
  }

  late final double size;
  late final Vec2 emitter;
  late final double emitterDegrees;
  late final Vec2 target;
  late final double targetRadius;
  late final int minBounces;
  late final int maxBounces;
  final List<RayMirror> mirrors = [];
  final List<Segment> walls = [];

  /// Turns a mirror by a number of steps. Returns false for fixed mirrors.
  bool rotate(int mirror, int delta) {
    final m = mirrors[mirror];
    if (m.fixed) return false;
    m.step = (m.step + delta) % m.steps;
    if (m.step < 0) m.step += m.steps;
    return true;
  }

  bool setStep(int mirror, int step) {
    final m = mirrors[mirror];
    if (m.fixed) return false;
    final next = step % m.steps;
    if (next == m.step) return false;
    m.step = next < 0 ? next + m.steps : next;
    return true;
  }

  RayTrace trace() {
    var pos = emitter;
    var dir = Vec2.fromDegrees(emitterDegrees);
    final points = <Vec2>[pos];
    var bounces = 0;
    var hit = false;
    final room = [
      Segment(const Vec2(0, 0), Vec2(size, 0)),
      Segment(Vec2(size, 0), Vec2(size, size)),
      Segment(Vec2(size, size), Vec2(0, size)),
      Segment(Vec2(0, size), const Vec2(0, 0)),
    ];
    final mirrorSegments = [for (final m in mirrors) m.segment];
    while (true) {
      double best = double.infinity;
      Segment? mirror;
      var stop = false;
      for (final seg in mirrorSegments) {
        final t = raySegment(pos, dir, seg);
        if (t != null && t < best) {
          best = t;
          mirror = seg;
        }
      }
      for (final seg in [...walls, ...room]) {
        final t = raySegment(pos, dir, seg);
        if (t != null && t < best) {
          best = t;
          mirror = null;
          stop = true;
        }
      }
      final tt = rayCircle(pos, dir, target, targetRadius);
      if (tt != null && tt < best) {
        points.add(pos + dir * tt);
        hit = true;
        break;
      }
      if (best == double.infinity) {
        points.add(pos + dir * size);
        break;
      }
      pos = pos + dir * best;
      points.add(pos);
      if (stop || mirror == null) break;
      if (bounces >= maxBounces) break;
      bounces++;
      dir = dir.reflect(mirror.normal).normalized;
    }
    var miss = double.infinity;
    for (var i = 1; i < points.length; i++) {
      final d = pointSegmentDistance(target, points[i - 1], points[i]) - targetRadius;
      if (d < miss) miss = d;
    }
    return RayTrace(points, hit, bounces, hit ? 0 : miss);
  }

  @override
  void reset() {
    for (final m in mirrors) {
      m.step = m.initialStep;
    }
  }

  @override
  Map<String, dynamic> snapshot() => {
    'steps': [for (final m in mirrors) m.step],
  };

  @override
  void restore(Map<String, dynamic> snapshot) {
    final steps = (snapshot['steps'] as List).cast<int>();
    if (steps.length != mirrors.length) throw ArgumentError('snapshot does not fit this level');
    for (var i = 0; i < mirrors.length; i++) {
      if (mirrors[i].fixed) {
        if (steps[i] != mirrors[i].initialStep) throw ArgumentError('snapshot moves a fixed mirror');
      } else {
        mirrors[i].step = steps[i] % mirrors[i].steps;
      }
    }
  }

  Outcome _judge(RayTrace t) {
    final detail = {
      'path': [for (final p in t.points) p.toJson()],
      'bounces': t.bounces,
    };
    if (t.hit && t.bounces >= minBounces) return Outcome.solved(detail);
    if (t.hit) {
      return Outcome.failed('too_direct', magnitude: (minBounces - t.bounces).toDouble(), detail: detail);
    }
    return Outcome.failed('missed', magnitude: t.miss, detail: detail);
  }

  @override
  Outcome evaluate() => _judge(trace());

  @override
  SimResult simulate() {
    final t = trace();
    final travel = (t.length / 220 * 60).round().clamp(24, 150);
    final b = TimelineBuilder(travel + 36);
    b.fill('beam', (i) => (i / travel).clamp(0.0, 1.0));
    b.ramp('glow', travel, travel + 24);
    return SimResult(_judge(t), b.build());
  }
}

class RayArchetype extends Archetype {
  const RayArchetype();

  @override
  String get id => 'ray_reflection';

  @override
  RayScene create(LevelSpec level) => RayScene(level);

  void _enumerate(RayScene scene, void Function() visit) {
    final turning = [
      for (var i = 0; i < scene.mirrors.length; i++)
        if (!scene.mirrors[i].fixed) i,
    ];
    void go(int k) {
      if (k == turning.length) {
        visit();
        return;
      }
      final m = scene.mirrors[turning[k]];
      for (var s = 0; s < m.steps; s++) {
        m.step = s;
        go(k + 1);
      }
    }

    go(0);
  }

  @override
  Solution? solve(LevelSpec level) {
    final scene = create(level);
    Map<String, dynamic>? found;
    _enumerate(scene, () {
      if (found == null && scene.evaluate().success) found = scene.snapshot();
    });
    final turning = scene.mirrors.where((m) => !m.fixed).length;
    return found == null ? null : Solution(found!, effort: turning);
  }

  @override
  double? winFraction(LevelSpec level) {
    final scene = create(level);
    var total = 0;
    var wins = 0;
    _enumerate(scene, () {
      total++;
      if (scene.evaluate().success) wins++;
    });
    return total == 0 ? 0 : wins / total;
  }
}
