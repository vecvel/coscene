import 'dart:math' as math;
import 'dart:ui';

import 'package:coscene_core/coscene_core.dart';

import '../draw.dart';
import '../palette.dart';
import '../scene_delegate.dart';

/// The mirror room: a lamp, turning mirrors, walls and a sensor.
class RayDelegate extends SceneDelegate<RayScene> {
  RayDelegate(super.scene);

  /// How close a finger must be to a mirror's pivot to take hold of it.
  static const double _reach = 10;

  /// Inside this distance the finger is too close to the pivot to aim with.
  static const double _deadZone = 4;

  int? _drag;

  Offset _o(Vec2 v) => Offset(v.x, v.y);

  /// The nearest turning mirror whose pivot is within reach of [p].
  int? _mirrorAt(Offset p) {
    int? hit;
    var best = _reach;
    for (var i = 0; i < scene.mirrors.length; i++) {
      final m = scene.mirrors[i];
      if (m.fixed) continue;
      final d = (p - _o(m.center)).distance;
      if (d <= best) {
        best = d;
        hit = i;
      }
    }
    return hit;
  }

  @override
  void onTap(Offset p) {
    final i = _mirrorAt(p);
    if (i == null) return;
    if (scene.rotate(i, 1)) {
      feedback(SceneFeedback.tick);
      changed();
    }
  }

  @override
  bool onDown(Offset p) {
    _drag = _mirrorAt(p);
    return _drag != null;
  }

  @override
  void onMove(Offset p) {
    final i = _drag;
    if (i == null) return;
    final m = scene.mirrors[i];
    final arm = p - _o(m.center);
    if (arm.distance <= _deadZone) return;
    final degrees = math.atan2(arm.dy, arm.dx) * 180 / math.pi;
    if (scene.setStep(i, (degrees / m.stepDegrees).round())) {
      feedback(SceneFeedback.tick);
      changed();
    }
  }

  @override
  void onUp(Offset p) => _drag = null;

  @override
  void sync() => _drag = null;

  /// Dashed first leg and a short stub of the second: a hint, not the answer.
  void _preview(Canvas canvas, List<Vec2> points) {
    if (points.length < 2) return;
    final paint = line(Palette.coral, 0.8);
    drawDashed(canvas, _o(points[0]), _o(points[1]), paint);
    if (points.length < 3) return;
    final a = _o(points[1]);
    final leg = _o(points[2]) - a;
    final length = leg.distance;
    if (length == 0) return;
    drawDashed(canvas, a, a + leg / length * math.min(10.0, length), paint);
  }

  /// The beam so far: [fraction] of the whole route, measured by length.
  void _beam(Canvas canvas, List<Vec2> points, double fraction) {
    if (points.length < 2) return;
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += points[i].distanceTo(points[i - 1]);
    }
    var left = total * fraction.clamp(0.0, 1.0);
    if (left <= 0) return;
    final path = Path()..moveTo(points[0].x, points[0].y);
    for (var i = 1; i < points.length && left > 0; i++) {
      final a = _o(points[i - 1]), b = _o(points[i]);
      final length = (b - a).distance;
      if (length == 0) continue;
      final end = left >= length ? b : a + (b - a) * (left / length);
      path.lineTo(end.dx, end.dy);
      left -= length;
    }
    canvas.drawPath(path, line(Palette.coral, 1.6));
  }

  @override
  void paint(Canvas canvas, PaintContext ctx) {
    final solved = ctx.finished && ctx.outcome!.success;
    final size = scene.size;

    // Room and walls.
    canvas.drawRect(Rect.fromLTWH(0.6, 0.6, size - 1.2, size - 1.2), line(Palette.ink, 1.2));
    for (final w in scene.walls) {
      canvas.drawLine(_o(w.a), _o(w.b), line(Palette.ink, 2.2));
    }

    // Last failed try: where each turned mirror used to point.
    final ghost = ctx.ghost?['steps'];
    if (ghost is List && !ctx.playing) {
      for (var i = 0; i < scene.mirrors.length && i < ghost.length; i++) {
        final m = scene.mirrors[i];
        final step = ghost[i];
        if (m.fixed || step is! int || step == m.step) continue;
        final half = Vec2.fromDegrees(step * m.stepDegrees, m.length / 2);
        canvas.drawLine(_o(m.center - half), _o(m.center + half), line(faint(Palette.ink, 0.3), 0.7));
      }
    }

    // Mirrors. The ones that turn carry a pivot.
    for (final m in scene.mirrors) {
      final s = m.segment;
      canvas.drawLine(_o(s.a), _o(s.b), line(m.fixed ? Palette.stone : Palette.slate, 2.4));
      if (m.fixed) continue;
      canvas.drawCircle(_o(m.center), 1.6, fill(Palette.cream));
      canvas.drawCircle(_o(m.center), 1.6, line(Palette.ink, 0.7));
    }

    // Sensor.
    final target = _o(scene.target);
    canvas.drawCircle(target, scene.targetRadius, fill(solved ? Palette.teal : Palette.mustard));
    canvas.drawCircle(target, scene.targetRadius, line(Palette.ink, 1));
    if (solved) canvas.drawCircle(target, scene.targetRadius + 2.5, line(Palette.teal, 0.8));

    // Aim hint while setting up, the real beam once submitted.
    final points = scene.trace().points;
    if (!ctx.playing) {
      _preview(canvas, points);
    } else {
      _beam(canvas, points, ctx.track('beam'));
      if (ctx.finished && !ctx.outcome!.success) {
        final end = _o(points.last);
        final cross = line(Palette.ink, 0.9);
        canvas.drawLine(end + const Offset(-1.06, -1.06), end + const Offset(1.06, 1.06), cross);
        canvas.drawLine(end + const Offset(-1.06, 1.06), end + const Offset(1.06, -1.06), cross);
      }
    }

    // Lamp, on top so the beam leaves from its nozzle.
    final emitter = _o(scene.emitter);
    canvas.drawCircle(emitter, 3.2, fill(Palette.ink));
    canvas.drawLine(emitter, emitter + _o(Vec2.fromDegrees(scene.emitterDegrees, 4.5)), line(Palette.coral, 2));
  }
}
