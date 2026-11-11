import 'dart:math' as math;
import 'dart:ui';

import 'package:coscene_core/coscene_core.dart';

import '../draw.dart';
import '../palette.dart';
import '../scene_delegate.dart';

/// A crank, a train of gears and a hand. Gears are dragged from the tray
/// onto empty pegs; the train slides so every pair stays in mesh.
class GearDelegate extends SceneDelegate<GearScene> {
  GearDelegate(super.scene) {
    sync();
  }

  static const double _axleY = 40;
  static const double _trayY = 85;
  static const int _standIn = 14;

  int? _drag;
  int? _dragFrom;
  Offset _dragPos = Offset.zero;
  late List<double> _shownX;

  /// Teeth shown on a spot. A gear being dragged is off its peg.
  int? _teeth(GearSpot spot) {
    final bolted = spot.fixedTeeth;
    if (bolted != null) return bolted;
    final t = scene.slots[spot.slot!];
    return t == null || t == _drag ? null : scene.tray[t];
  }

  List<GearSpot> _spotsOn(int axle) => [
    if (axle > 0) scene.stages[axle - 1].driven,
    if (axle < scene.stages.length) scene.stages[axle].driver,
  ];

  /// Scale (units per tooth) and where each axle wants to be.
  ({double k, List<double> x}) _layout() {
    final xs = <double>[0];
    for (final st in scene.stages) {
      xs.add(xs.last + (_teeth(st.driver) ?? _standIn) + (_teeth(st.driven) ?? _standIn));
    }
    var left = double.infinity, right = -double.infinity, biggest = 0.0;
    for (var a = 0; a < xs.length; a++) {
      final m = _spotsOn(a).map((s) => (_teeth(s) ?? _standIn).toDouble()).reduce(math.max);
      left = math.min(left, xs[a] - m);
      right = math.max(right, xs[a] + m);
      biggest = math.max(biggest, m);
    }
    final k = math.min(86 / (right - left), 20 / biggest);
    final shift = 50 - (left + right) / 2 * k;
    return (k: k, x: [for (final x in xs) x * k + shift]);
  }

  @override
  void sync() => _shownX = _layout().x;

  @override
  bool tick(double dt) {
    final goal = _layout().x;
    var moving = false;
    for (var i = 0; i < goal.length; i++) {
      final gap = goal[i] - _shownX[i];
      if (gap.abs() > 0.01) {
        _shownX[i] += gap * math.min(1, dt * 14);
        moving = true;
      } else {
        _shownX[i] = goal[i];
      }
    }
    return moving;
  }

  Offset _home(int tray) => Offset(12 + tray * 76 / (scene.tray.length - 1), _trayY);
  double _trayRadius(int tray) => (scene.tray[tray] * 0.2).clamp(4.0, 9.0);

  /// The axle with a peg nearest to [p], if close enough to drop on.
  int? _pegAxleNear(Offset p) {
    int? best;
    var bestDistance = 16.0;
    for (var a = 0; a < _shownX.length; a++) {
      if (!_spotsOn(a).any((s) => s.slot != null)) continue;
      final d = (p - Offset(_shownX[a], _axleY)).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = a;
      }
    }
    return best;
  }

  /// The peg on an axle to drop onto: an empty one if there is one.
  int _slotOn(int axle) {
    final pegs = [
      for (final s in _spotsOn(axle))
        if (s.slot != null) s.slot!,
    ];
    return pegs.firstWhere((s) => scene.slots[s] == null || scene.slots[s] == _drag, orElse: () => pegs.first);
  }

  /// Tray index of the player's gear on the train under [p], smallest first.
  int? _placedAt(Offset p) {
    final k = _layout().k;
    int? hit;
    var smallest = double.infinity;
    for (var a = 0; a < _shownX.length; a++) {
      for (final s in _spotsOn(a)) {
        final slot = s.slot;
        final t = slot == null ? null : scene.slots[slot];
        if (t == null) continue;
        final r = scene.tray[t] * k;
        if ((p - Offset(_shownX[a], _axleY)).distance <= r + 3 && r < smallest) {
          smallest = r;
          hit = t;
        }
      }
    }
    return hit;
  }

  @override
  bool onDown(Offset p) {
    int? hit;
    for (var t = 0; t < scene.tray.length; t++) {
      if (scene.slotOf(t) == null && (p - _home(t)).distance <= _trayRadius(t) + 4) hit = t;
    }
    hit ??= _placedAt(p);
    if (hit == null) return false;
    _dragFrom = scene.slotOf(hit);
    _drag = hit;
    _dragPos = p;
    feedback(SceneFeedback.lift);
    return true;
  }

  @override
  void onMove(Offset p) => _dragPos = p;

  @override
  void onUp(Offset p) {
    final t = _drag;
    if (t == null) return;
    final from = _dragFrom;
    final axle = _pegAxleNear(p);
    final slot = axle == null ? null : _slotOn(axle);
    _drag = null;
    _dragFrom = null;
    if (slot != null) {
      if (slot == from) return;
      scene.assign(slot, t);
      feedback(SceneFeedback.snap);
      changed();
    } else if (from != null) {
      scene.assign(from, null);
      feedback(SceneFeedback.tick);
      changed();
    }
  }

  @override
  void onTap(Offset p) {
    final t = _placedAt(p);
    final slot = t == null ? null : scene.slotOf(t);
    if (slot == null) return;
    scene.assign(slot, null);
    feedback(SceneFeedback.tick);
    changed();
  }

  void _gear(
    Canvas canvas,
    Offset c,
    int teeth,
    double r,
    double phi,
    Color color,
    Color label, {
    bool numbered = true,
  }) {
    final depth = math.min(2.2, r * 0.22);
    final inner = r - depth / 2, outer = r + depth / 2;
    final step = 2 * math.pi / teeth;
    final path = Path();
    for (var t = 0; t < teeth; t++) {
      final base = phi + t * step;
      const at = [-0.3, -0.14, 0.14, 0.3];
      for (var q = 0; q < 4; q++) {
        final a = base + at[q] * step;
        final rr = q == 0 || q == 3 ? inner : outer;
        final pt = c + Offset(math.cos(a), math.sin(a)) * rr;
        if (t == 0 && q == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
    }
    path.close();
    canvas.drawPath(path, fill(color));
    canvas.drawPath(path, line(Palette.ink, 0.45));
    canvas.drawCircle(c, 1.2, fill(Palette.cream));
    if (numbered && r >= 5) drawLabel(canvas, '$teeth', c + Offset(0, r * 0.52), size: 3.4, color: label);
  }

  void _dashedCircle(Canvas canvas, Offset c, double r, Paint paint) {
    final rect = Rect.fromCircle(center: c, radius: r);
    for (var i = 0; i < 18; i++) {
      canvas.drawArc(rect, i * math.pi / 9, math.pi / 18, false, paint);
    }
  }

  @override
  void paint(Canvas canvas, PaintContext ctx) {
    final k = _layout().k;
    final crank = ctx.track('crank');
    final alpha = crank * 2 * math.pi;
    final speeds = scene.speeds;
    final solved = ctx.finished && ctx.outcome!.success;

    // Angle of every gear, keeping meshed teeth in step.
    final driverPhi = <double>[], drivenPhi = <double>[];
    var broken = false;
    for (var i = 0; i < scene.stages.length; i++) {
      final a = _teeth(scene.stages[i].driver), b = _teeth(scene.stages[i].driven);
      final phi = i == 0 ? alpha : drivenPhi.last;
      driverPhi.add(broken ? 0 : phi);
      if (broken || a == null || b == null) {
        broken = true;
        drivenPhi.add(0);
      } else {
        drivenPhi.add(math.pi + math.pi / b - phi * a / b);
      }
    }

    // Peg the dragged gear would drop onto.
    if (_drag != null) {
      final axle = _pegAxleNear(_dragPos);
      if (axle != null) {
        canvas.drawCircle(Offset(_shownX[axle], _axleY), _standIn * k + 1.5, line(Palette.mustard, 1));
      }
    }

    for (var a = 0; a < _shownX.length; a++) {
      final c = Offset(_shownX[a], _axleY);
      final onAxle = [
        if (a > 0) (scene.stages[a - 1].driven, drivenPhi[a - 1]),
        if (a < scene.stages.length) (scene.stages[a].driver, driverPhi[a]),
      ]..sort((x, y) => (_teeth(y.$1) ?? 0).compareTo(_teeth(x.$1) ?? 0));
      for (final (spot, phi) in onAxle) {
        final teeth = _teeth(spot);
        if (teeth == null) {
          _dashedCircle(canvas, c, _standIn * k, line(Palette.stone, 0.8));
          canvas.drawCircle(c, 1.2, fill(Palette.ink));
        } else if (spot.slot == null) {
          _gear(canvas, c, teeth, teeth * k, phi, Palette.slate, Palette.cream);
        } else {
          _gear(canvas, c, teeth, teeth * k, phi, Palette.orange, Palette.ink);
        }
      }
    }

    // Crank handle on the first axle.
    final first = Offset(_shownX.first, _axleY);
    final reach = (_teeth(scene.stages.first.driver) ?? _standIn) * k + 5;
    final knob = first + Offset(math.cos(alpha - math.pi / 2), math.sin(alpha - math.pi / 2)) * reach;
    canvas.drawLine(first, knob, line(Palette.ink, 1.6));
    canvas.drawCircle(knob, 2.4, fill(Palette.orange));
    canvas.drawCircle(knob, 2.4, line(Palette.ink, 0.7));

    // Dial and hand on the last axle.
    final last = Offset(_shownX.last, _axleY);
    final dial = (_teeth(scene.stages.last.driven) ?? _standIn) * k + 6;
    canvas.drawArc(
      Rect.fromCircle(center: last, radius: dial),
      -math.pi * 0.8,
      math.pi * 0.6,
      false,
      line(Palette.stone, 0.8),
    );
    canvas.drawLine(last - Offset(0, dial - 2), last - Offset(0, dial + 2), line(Palette.mustard, 1.4));
    final handAngle = -math.pi / 2 + alpha * speeds.last;
    canvas.drawLine(
      last,
      last + Offset(math.cos(handAngle), math.sin(handAngle)) * dial,
      line(solved ? Palette.teal : Palette.ink, 1.8),
    );

    // Turn counters: rings that fill as each whole turn completes.
    void rings(double centerX, int count, double done, Color color) {
      final start = (centerX - (count - 1) * 2.5).clamp(3.0, 97.0 - (count - 1) * 5);
      for (var i = 0; i < count; i++) {
        final c = Offset(start + i * 5, 71);
        if (done >= i + 1 - 1e-3) canvas.drawCircle(c, 1.8, fill(color));
        canvas.drawCircle(c, 1.8, line(Palette.ink, 0.6));
      }
      final extra = ((done + 1e-3).floor() - count).clamp(0, 3);
      for (var i = 0; i < extra; i++) {
        canvas.drawCircle(Offset(start + (count + i) * 5, 71), 1.4, fill(Palette.coral));
      }
    }

    rings(first.dx, scene.inputTurns, crank, Palette.orange);
    rings(last.dx, scene.targetTurns.round(), crank * speeds.last.abs(), solved ? Palette.teal : Palette.ink);

    // Tray.
    for (var t = 0; t < scene.tray.length; t++) {
      if (t == _drag) continue;
      if (scene.slotOf(t) != null) {
        canvas.drawCircle(_home(t), 1, fill(Palette.stone));
      } else {
        _gear(canvas, _home(t), scene.tray[t], _trayRadius(t), 0, Palette.orange, Palette.ink, numbered: false);
        drawLabel(canvas, '${scene.tray[t]}', _home(t) + Offset(0, _trayRadius(t) + 4), size: 3.4);
      }
    }
    final drag = _drag;
    if (drag != null) {
      _gear(canvas, _dragPos, scene.tray[drag], _trayRadius(drag), 0, Palette.orange, Palette.ink, numbered: false);
    }
  }
}
