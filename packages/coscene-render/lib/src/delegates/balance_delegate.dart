import 'dart:math' as math;
import 'dart:ui';

import 'package:coscene_core/coscene_core.dart';

import '../draw.dart';
import '../palette.dart';
import '../scene_delegate.dart';

/// The crane arm: crates hang from hooks, the arm swings when lifted.
class BalanceDelegate extends SceneDelegate<BalanceScene> {
  BalanceDelegate(super.scene);

  static const Offset _pivot = Offset(50, 30);
  static const double _trayY = 80;
  static const double _dropLine = 64;

  int? _drag;
  Offset _dragPos = Offset.zero;

  double get _spacing => 42 / scene.halfSpan;
  double get _crateWidth => math.min(9.5, _spacing * 0.86);
  double _crateHeight(int weight) => 4.5 + 1.7 * weight;

  List<int> get _movable => [
    for (var i = 0; i < scene.loads.length; i++)
      if (!scene.loads[i].fixed) i,
  ];

  Offset _trayCenter(int load) {
    final m = _movable;
    final k = m.indexOf(load);
    return Offset(50 + (k - (m.length - 1) / 2) * 14, _trayY);
  }

  /// Where a hook is when the arm is tilted by [angle].
  Offset _hook(int slot, double angle, double lift) =>
      _pivot + Offset(math.cos(angle), math.sin(angle)) * (slot * _spacing) - Offset(0, lift);

  Offset _crateCenter(int load, {double angle = 0, double lift = 0}) {
    if (_drag == load) return _dragPos;
    final l = scene.loads[load];
    final slot = l.slot;
    if (slot == null) return _trayCenter(load);
    return _hook(slot, angle, lift) + Offset(0, 4 + _crateHeight(l.weight) / 2);
  }

  int? _nearestFreeSlot(Offset p, int load) {
    if (p.dy > _dropLine) return null;
    int? best;
    var bestDistance = _spacing * 1.3;
    for (var s = -scene.halfSpan; s <= scene.halfSpan; s++) {
      if (!scene.canPlace(load, s)) continue;
      final d = (p.dx - (_pivot.dx + s * _spacing)).abs();
      if (d < bestDistance) {
        bestDistance = d;
        best = s;
      }
    }
    return best;
  }

  @override
  bool onDown(Offset p) {
    int? hit;
    var best = double.infinity;
    for (final i in _movable) {
      final c = _crateCenter(i);
      final reach = math.max(_crateWidth, _crateHeight(scene.loads[i].weight)) / 2 + 4;
      final d = (p - c).distance;
      if (d < reach && d < best) {
        best = d;
        hit = i;
      }
    }
    if (hit == null) return false;
    _drag = hit;
    _dragPos = p;
    feedback(SceneFeedback.lift);
    return true;
  }

  @override
  void onMove(Offset p) => _dragPos = p;

  @override
  void onUp(Offset p) {
    final load = _drag;
    if (load == null) return;
    _drag = null;
    final before = scene.loads[load].slot;
    if (p.dy > _dropLine) {
      if (before != null) {
        scene.place(load, null);
        feedback(SceneFeedback.tick);
        changed();
      }
      return;
    }
    final slot = _nearestFreeSlot(p, load);
    if (slot == null) {
      feedback(SceneFeedback.reject);
    } else if (slot != before) {
      scene.place(load, slot);
      feedback(SceneFeedback.snap);
      changed();
    }
  }

  void _crate(Canvas canvas, Offset center, BalanceLoad load, {bool ghost = false}) {
    final rect = Rect.fromCenter(center: center, width: _crateWidth, height: _crateHeight(load.weight));
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(1));
    if (ghost) {
      canvas.drawRRect(shape, line(faint(Palette.ink, 0.35), 0.5));
      return;
    }
    canvas.drawRRect(shape, fill(load.fixed ? Palette.slate : Palette.orange));
    drawPips(canvas, rect.deflate(1.1), load.weight, load.fixed ? Palette.cream : Palette.ink);
  }

  @override
  void paint(Canvas canvas, PaintContext ctx) {
    final angle = _drag == null ? ctx.track('angle') : 0.0;
    final lift = ctx.track('lift') * 9;
    final solved = ctx.finished && ctx.outcome!.success;

    // Dock and water.
    canvas.drawRect(const Rect.fromLTWH(0, 94, 100, 6), fill(Palette.slate));
    canvas.drawRect(const Rect.fromLTWH(0, 90, 100, 4), fill(Palette.stone));

    // Cable and arm.
    final pivot = _pivot - Offset(0, lift);
    canvas.drawLine(Offset(pivot.dx, -4), pivot, line(Palette.ink, 1.2, cap: StrokeCap.butt));
    final arm = Offset(math.cos(angle), math.sin(angle)) * 45;
    canvas.drawLine(pivot - arm, pivot + arm, line(solved ? Palette.teal : Palette.ink, 2.6));

    // Hooks. Broken ones show as a cross.
    for (var s = -scene.halfSpan; s <= scene.halfSpan; s++) {
      if (s == 0) continue;
      final h = _hook(s, angle, lift);
      if (scene.blocked.contains(s)) {
        final p = line(Palette.stone, 0.8);
        canvas.drawLine(h + const Offset(-1.2, 1.4), h + const Offset(1.2, 3.8), p);
        canvas.drawLine(h + const Offset(1.2, 1.4), h + const Offset(-1.2, 3.8), p);
      } else {
        canvas.drawLine(h, h + const Offset(0, 3), line(Palette.ink, 0.7));
      }
    }
    canvas.drawCircle(pivot, 2.6, fill(Palette.cream));
    canvas.drawCircle(pivot, 2.6, line(Palette.ink, 1.3));

    // Where the dragged crate would land.
    final drag = _drag;
    if (drag != null) {
      final slot = _nearestFreeSlot(_dragPos, drag);
      if (slot != null) {
        canvas.drawCircle(_hook(slot, 0, 0) + const Offset(0, 3), 2.2, line(Palette.mustard, 1));
      }
    }

    // Last failed try, as outlines.
    final ghost = ctx.ghost?['slots'];
    if (ghost is List && !ctx.playing) {
      final m = _movable;
      for (var k = 0; k < m.length && k < ghost.length; k++) {
        final slot = ghost[k];
        final load = scene.loads[m[k]];
        if (slot is int && slot != load.slot) {
          _crate(canvas, _hook(slot, 0, 0) + Offset(0, 4 + _crateHeight(load.weight) / 2), load, ghost: true);
        }
      }
    }

    // Crates, the dragged one last so it stays on top.
    for (var i = 0; i < scene.loads.length; i++) {
      if (i == drag) continue;
      final load = scene.loads[i];
      final slot = load.slot;
      if (slot != null) {
        final h = _hook(slot, angle, lift);
        canvas.drawLine(h + const Offset(0, 3), h + const Offset(0, 4), line(Palette.ink, 0.7));
      }
      _crate(canvas, _crateCenter(i, angle: angle, lift: lift), load);
    }
    if (drag != null) _crate(canvas, _dragPos, scene.loads[drag]);
  }
}
