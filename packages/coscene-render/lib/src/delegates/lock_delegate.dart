import 'dart:math' as math;
import 'dart:ui';

import 'package:coscene_core/coscene_core.dart';

import '../draw.dart';
import '../palette.dart';
import '../scene_delegate.dart';

/// Linked dials under a bolt. Tapping a dial's right half turns it forward,
/// its left half turns it back.
class LockDelegate extends SceneDelegate<LockScene> {
  LockDelegate(super.scene) {
    sync();
  }

  static const double _row = 56;

  late List<int> _seen;
  late List<double> _goal;
  late List<double> _shown;

  double get _radius => switch (scene.dials.length) {
    1 || 2 => 17,
    3 => 13.5,
    4 => 10.5,
    _ => 8.5,
  };

  Offset _center(int i) {
    final n = scene.dials.length;
    if (n == 1) return const Offset(50, _row);
    final edge = _radius + 6;
    return Offset(edge + i * (100 - 2 * edge) / (n - 1), _row);
  }

  @override
  void sync() {
    _seen = [for (final d in scene.dials) d.value];
    _goal = [for (final d in scene.dials) d.value.toDouble()];
    _shown = List.of(_goal);
  }

  @override
  bool tick(double dt) {
    var moving = false;
    for (var i = 0; i < scene.dials.length; i++) {
      final d = scene.dials[i];
      if (d.value != _seen[i]) {
        // Count the short way round, so 5 -> 0 on six positions is one step.
        var delta = (d.value - _seen[i]) % d.positions;
        if (delta > d.positions / 2) delta -= d.positions;
        _goal[i] += delta;
        _seen[i] = d.value;
      }
      final gap = _goal[i] - _shown[i];
      if (gap.abs() > 0.001) {
        _shown[i] += gap * math.min(1, dt * 16);
        moving = true;
      } else {
        _shown[i] = _goal[i];
      }
    }
    return moving;
  }

  @override
  void onTap(Offset p) {
    for (var i = 0; i < scene.dials.length; i++) {
      final c = _center(i);
      if ((p - c).distance > _radius + 6) continue;
      scene.turn(i, p.dx >= c.dx ? 1 : -1);
      feedback(SceneFeedback.tick);
      changed();
      return;
    }
  }

  Offset _onRim(int dial, double position, double radius) {
    final a = -math.pi / 2 + position * 2 * math.pi / scene.dials[dial].positions;
    return _center(dial) + Offset(math.cos(a), math.sin(a)) * radius;
  }

  void _link(Canvas canvas, int from, int to, bool reversed) {
    final up = from < to;
    final r = _radius;
    final a = _center(from) + Offset(0, up ? -r : r);
    final b = _center(to) + Offset(0, up ? -r : r);
    final bulge = (12 + 4 * (from - to).abs()) * (up ? -1 : 1);
    final control = Offset((a.dx + b.dx) / 2, a.dy + bulge);
    Offset at(double t) => a * ((1 - t) * (1 - t)) + control * (2 * t * (1 - t)) + b * (t * t);
    final paint = line(Palette.slate, 0.9);
    const steps = 24;
    for (var k = 0; k < steps; k++) {
      if (reversed && k.isOdd) continue;
      canvas.drawLine(at(k / steps), at((k + 1) / steps), paint);
    }
    final tail = at(0.94);
    drawArrowHead(canvas, b, math.atan2(b.dy - tail.dy, b.dx - tail.dx), 3, fill(Palette.slate));
  }

  @override
  void paint(Canvas canvas, PaintContext ctx) {
    final solved = ctx.finished && ctx.outcome!.success;
    final r = _radius;

    // Bolt.
    const housing = Rect.fromLTRB(20, 10, 80, 16);
    canvas.drawRect(housing, fill(Palette.sand));
    // The bolt slides inside the housing and never past its end, even on
    // the spring's overshoot.
    final shift = (ctx.track('open') * 16).clamp(0.0, 16.0) + ctx.track('rattle') * 0.6;
    canvas.save();
    canvas.clipRect(housing.deflate(0.5));
    canvas.drawRect(Rect.fromLTWH(37 + shift, 11.3, 26, 3.4), fill(solved ? Palette.teal : Palette.ink));
    canvas.restore();
    canvas.drawRect(housing, line(Palette.ink, 1));

    // Linkages between dials.
    for (var i = 0; i < scene.dials.length; i++) {
      for (var j = 0; j < scene.dials.length; j++) {
        if (i != j && scene.links[i][j] != 0) _link(canvas, i, j, scene.links[i][j] < 0);
      }
    }

    final ghost = ctx.ghost?['values'];
    for (var i = 0; i < scene.dials.length; i++) {
      final d = scene.dials[i];
      final c = _center(i);
      canvas.drawCircle(c, r, fill(Palette.sand));
      canvas.drawCircle(c, r, line(Palette.ink, 1.2));
      for (var k = 0; k < d.positions; k++) {
        canvas.drawLine(_onRim(i, k.toDouble(), r - 1), _onRim(i, k.toDouble(), r - 3), line(Palette.ink, 0.6));
      }

      // The mark to reach, outside the rim.
      final tip = _onRim(i, d.target.toDouble(), r + 1.2);
      final a = math.atan2(c.dy - tip.dy, c.dx - tip.dx);
      drawArrowHead(canvas, tip, a, 4, fill(Palette.mustard));

      if (ghost is List && !ctx.playing && i < ghost.length && ghost[i] != d.value) {
        canvas.drawCircle(_onRim(i, (ghost[i] as int).toDouble(), r - 5), 1, fill(faint(Palette.ink, 0.35)));
      }

      // Only a correct Open shows which dials were right; before that the
      // player judges by eye, like the other puzzles.
      final color = solved ? Palette.teal : Palette.ink;
      canvas.drawLine(c, _onRim(i, _shown[i], r * 0.72), line(color, 1.6));
      canvas.drawCircle(c, 1.6, fill(color));
    }
  }
}
