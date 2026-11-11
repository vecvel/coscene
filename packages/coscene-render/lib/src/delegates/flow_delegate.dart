import 'dart:math' as math;
import 'dart:ui';

import 'package:coscene_core/coscene_core.dart';

import '../draw.dart';
import '../palette.dart';
import '../scene_delegate.dart';

/// Water tanks under a pipe. Each tank has a tap slider; a timer sets how
/// long the water runs.
class FlowDelegate extends SceneDelegate<FlowScene> {
  FlowDelegate(super.scene);

  static const double _floor = 90;
  static const double _unit = 4.6;
  static const double _sliderTop = 18;
  static const double _sliderBottom = 30;
  static const Offset _timer = Offset(89, 22);

  int? _drag;

  /// Outer rectangle of every tank, left to right.
  List<Rect> _tanks() {
    const left = 4.0, right = 78.0;
    final n = scene.tanks.length;
    var widths = [for (final t in scene.tanks) 9 + 5 * t.width];
    final total = widths.fold<double>(0, (a, b) => a + b);
    var gap = (right - left - total) / (n + 1);
    if (gap < 3) {
      final s = (right - left - 3 * (n + 1)) / total;
      widths = [for (final w in widths) w * s];
      gap = 3;
    }
    final out = <Rect>[];
    var x = left + gap;
    for (var i = 0; i < n; i++) {
      final h = scene.tanks[i].height * _unit;
      out.add(Rect.fromLTWH(x, _floor - h, widths[i], h));
      x += widths[i] + gap;
    }
    return out;
  }

  double _knobY(FlowValve v) => _sliderBottom - v.rate / v.max * (_sliderBottom - _sliderTop);

  void _setFromY(int valve, double y) {
    final v = scene.valves[valve];
    final rate = ((_sliderBottom - y) / (_sliderBottom - _sliderTop) * v.max).round();
    if (scene.setRate(valve, rate)) {
      feedback(SceneFeedback.tick);
      changed();
    }
  }

  @override
  bool onDown(Offset p) {
    if (p.dy < 12 || p.dy > 36) return false;
    final tanks = _tanks();
    int? hit;
    var best = 9.0;
    for (var i = 0; i < scene.valves.length; i++) {
      final d = (p.dx - tanks[scene.valves[i].tank].center.dx).abs();
      if (d < best) {
        best = d;
        hit = i;
      }
    }
    if (hit == null) return false;
    _drag = hit;
    _setFromY(hit, p.dy);
    return true;
  }

  @override
  void onMove(Offset p) {
    final d = _drag;
    if (d != null) _setFromY(d, p.dy);
  }

  @override
  void onUp(Offset p) => _drag = null;

  @override
  void onTap(Offset p) {
    if (scene.duration.isFixed || (p - _timer).distance > 10) return;
    scene.duration.index = (scene.duration.index + 1) % scene.duration.count;
    feedback(SceneFeedback.tick);
    changed();
  }

  @override
  void paint(Canvas canvas, PaintContext ctx) {
    final tanks = _tanks();
    final fillAmount = ctx.track('fill');
    final levels = ctx.playing ? (ctx.outcome!.detail['levels'] as List).cast<num>() : null;

    // Pump limit: one square per unit of flow it can give.
    final supply = scene.supply;
    if (supply != null) {
      final asked = scene.valves.fold<int>(0, (a, v) => a + v.rate);
      for (var i = 0; i < supply.round(); i++) {
        final color = asked > supply ? Palette.coral : (i < asked ? Palette.slate : Palette.stone);
        canvas.drawRect(Rect.fromLTWH(4 + i * 3.2, 2.6, 2.4, 2.4), fill(color));
      }
    }

    // Main pipe and a drop to every tank.
    final pipe = line(Palette.ink, 1.6, cap: StrokeCap.square);
    canvas.drawLine(const Offset(4, 10), Offset(tanks.last.center.dx, 10), pipe);
    for (final r in tanks) {
      canvas.drawLine(Offset(r.center.dx, 10), Offset(r.center.dx, 16), pipe);
    }

    for (var i = 0; i < scene.tanks.length; i++) {
      final tank = scene.tanks[i];
      final r = tanks[i];
      final valve = scene.valves.indexWhere((v) => v.tank == i);
      final rate = valve < 0 ? 0 : scene.valves[valve].rate;

      // Water, stream and spill while the result plays.
      if (levels != null) {
        final raw = levels[i] * fillAmount;
        final level = math.min(raw, tank.height) * _unit;
        if (level > 0) {
          canvas.drawRect(Rect.fromLTRB(r.left, _floor - level, r.right, _floor), fill(Palette.slate));
        }
        if (fillAmount < 1 && rate > 0) {
          canvas.drawLine(
            Offset(r.center.dx, _sliderBottom),
            Offset(r.center.dx, _floor - level),
            line(Palette.slate, 0.6 + rate * 0.35, cap: StrokeCap.butt),
          );
        }
        if (raw > tank.height + 1e-6) {
          final spill = line(Palette.slate, 1, cap: StrokeCap.butt);
          canvas.drawLine(Offset(r.left - 1.2, r.top), Offset(r.left - 1.2, _floor), spill);
          canvas.drawLine(Offset(r.right + 1.2, r.top), Offset(r.right + 1.2, _floor), spill);
          canvas.drawRect(Rect.fromLTRB(r.left - 3, _floor, r.right + 3, _floor + 1.4), fill(Palette.slate));
        }
      }

      // Where the water reached on the last failed try.
      final ghost = ctx.ghost;
      if (ghost != null && !ctx.playing && valve >= 0) {
        final rates = (ghost['rates'] as List).cast<int>();
        final asked = rates.fold<int>(0, (a, b) => a + b);
        final pressure = supply != null && asked > supply ? supply / asked : 1.0;
        final was = math.min(
          rates[valve] * pressure * scene.duration.valueAt(ghost['duration'] as int) / tank.width,
          tank.height,
        );
        if (was > 0) {
          final y = _floor - was * _unit;
          drawDashed(canvas, Offset(r.left + 1, y), Offset(r.right - 1, y), line(faint(Palette.ink, 0.4), 0.5));
        }
      }

      // Walls and height marks.
      final wall = line(Palette.ink, 1.2, cap: StrokeCap.square);
      canvas.drawLine(r.topLeft, r.bottomLeft, wall);
      canvas.drawLine(r.bottomLeft, r.bottomRight, wall);
      canvas.drawLine(r.bottomRight, r.topRight, wall);
      for (var h = 1; h < tank.height; h++) {
        final y = _floor - h * _unit;
        canvas.drawLine(Offset(r.left + 0.6, y), Offset(r.left + 2.4, y), line(Palette.ink, 0.5));
      }

      // The line to reach.
      var mark = Palette.mustard;
      if (ctx.finished && levels != null) {
        mark = (levels[i] - tank.target).abs() <= scene.tolerance + 1e-9 ? Palette.teal : Palette.coral;
      }
      final ty = _floor - tank.target * _unit;
      canvas.drawLine(Offset(r.left, ty), Offset(r.right, ty), line(mark, 1, cap: StrokeCap.butt));
      canvas.drawPath(
        Path()
          ..moveTo(r.right + 1.2, ty)
          ..lineTo(r.right + 4, ty - 1.8)
          ..lineTo(r.right + 4, ty + 1.8)
          ..close(),
        fill(mark),
      );

      // Tap slider.
      if (valve >= 0) {
        final v = scene.valves[valve];
        final x = r.center.dx;
        canvas.drawLine(Offset(x, _sliderTop), Offset(x, _sliderBottom), line(Palette.stone, 1.4));
        for (var k = 0; k <= v.max; k++) {
          final y = _sliderBottom - k / v.max * (_sliderBottom - _sliderTop);
          canvas.drawLine(Offset(x + 2.2, y), Offset(x + 4, y), line(Palette.ink, 0.5));
        }
        final knob = Offset(x, _knobY(v));
        canvas.drawCircle(knob, 2.6, fill(Palette.orange));
        canvas.drawCircle(knob, 2.6, line(Palette.ink, 0.8));
      }
    }

    // Timer.
    canvas.drawCircle(_timer, 7, fill(Palette.sand));
    canvas.drawCircle(_timer, 7, line(Palette.ink, 1));
    if (!scene.duration.isFixed) {
      for (var k = 0; k < scene.duration.count; k++) {
        final a = -math.pi / 2 + k * 2 * math.pi / scene.duration.count;
        final dir = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(
          _timer + dir * 8.4,
          _timer + dir * 9.8,
          line(k == scene.duration.index ? Palette.orange : Palette.ink, k == scene.duration.index ? 1.2 : 0.5),
        );
      }
    }
    final seconds = scene.duration.value;
    drawLabel(canvas, seconds == seconds.roundToDouble() ? '${seconds.round()}' : '$seconds', _timer, size: 6);
  }
}
