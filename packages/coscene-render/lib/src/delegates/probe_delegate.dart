import 'dart:ui';

import 'package:coscene_core/coscene_core.dart';

import '../draw.dart';
import '../palette.dart';
import '../scene_delegate.dart';
import 'kit.dart';

/// A number line, the checks so far, and the next value to check. Drag along
/// the line or use − and + to choose it.
class ProbeDelegate extends SceneDelegate<ProbeScene> {
  ProbeDelegate(super.scene);

  static const double _lineY = 30;
  static const Rect _line = Rect.fromLTWH(margin + 2, _lineY, 100 - 2 * margin - 4, 6);
  final List<Hit> _hits = [];

  int _valueAt(double x) {
    final t = ((x - _line.left) / _line.width).clamp(0.0, 1.0);
    return (scene.lo0 + t * (scene.hi0 - scene.lo0)).round();
  }

  double _xOf(int v) => _line.left + (v - scene.lo0) / (scene.hi0 - scene.lo0) * _line.width;

  void _set(int v) {
    final next = v.clamp(scene.lo0, scene.hi0);
    if (next == scene.pick) return;
    scene.pick = next;
    feedback(SceneFeedback.tick);
    changed();
  }

  @override
  bool onDown(Offset p) {
    if (_line.inflate(5).contains(p)) {
      _set(_valueAt(p.dx));
      return true;
    }
    return false;
  }

  @override
  void onMove(Offset p) => _set(_valueAt(p.dx));

  @override
  void onTap(Offset p) => tapHits(_hits, p);

  @override
  void paint(Canvas canvas, PaintContext ctx) {
    _hits.clear();
    final bisect = scene.mode == 'bisect';

    // Checks left, as dots.
    final left = scene.spent ? scene.budget : scene.checksLeft;
    for (var i = 0; i < scene.budget; i++) {
      final c = Offset(50 + (i - (scene.budget - 1) / 2) * 5, 8);
      canvas.drawCircle(c, 1.5, i < left ? fill(Palette.orange) : line(Palette.stone, 0.6));
    }

    // The line: still possible in white, ruled out in sand.
    tile(canvas, _line, Palette.sand, radius: 1.6);
    if (!scene.spent) {
      final alive = Rect.fromLTRB(_xOf(scene.lo) - 0.6, _line.top, _xOf(scene.hi) + 0.6, _line.bottom);
      tile(canvas, alive, scene.candidates == 1 ? Palette.tealTint : Palette.white, radius: 1.6);
    }
    for (final (v, x) in [(scene.lo0, _line.left), (scene.hi0, _line.right)]) {
      drawLabel(
        canvas,
        '$v',
        Offset(x, _lineY + 10),
        size: 3,
        color: Palette.inkSoft,
        weight: FontWeight.w500,
        mono: true,
      );
    }
    if (!scene.spent && scene.candidates < scene.hi0 - scene.lo0 + 1) {
      final text = scene.candidates == 1 ? '${scene.lo}' : '${scene.lo} – ${scene.hi}';
      drawLabel(canvas, text, Offset(50, _lineY - 7), size: 4, color: Palette.ink, weight: FontWeight.w500);
    }

    // Earlier checks as small marks above the line.
    for (final c in scene.spent ? const <({int value, String answer})>[] : scene.checks) {
      final x = _xOf(c.value);
      final good = c.answer == 'higher' || c.answer == 'good';
      canvas.drawLine(Offset(x, _line.top - 1.6), Offset(x, _line.bottom), line(Palette.ink, 0.5));
      final sign = switch (c.answer) {
        'higher' => '▲',
        'lower' => '▼',
        'good' => '✓',
        'bad' => '✗',
        _ => '●',
      };
      drawLabel(canvas, sign, Offset(x, _line.top - 3.6), size: 3, color: good ? Palette.teal : Palette.coralDeep);
    }

    // The value about to be checked.
    final px = _xOf(scene.pick);
    canvas.drawLine(Offset(px, _line.top - 0.8), Offset(px, _line.bottom + 0.8), line(Palette.orange, 1.1));

    final minus = const Rect.fromLTWH(18, 51, 15, 12), plus = const Rect.fromLTWH(67, 51, 15, 12);
    button(canvas, minus, '−');
    button(canvas, plus, '+');
    _hits
      ..add(Hit(minus, () => _set(scene.pick - 1)))
      ..add(Hit(plus, () => _set(scene.pick + 1)));
    drawLabel(canvas, '${scene.pick}', const Offset(50, 57), size: 8.4, weight: FontWeight.w600);

    // The most recent answers, newest first.
    final recent = scene.spent ? const <({int value, String answer})>[] : scene.checks.reversed.take(3).toList();
    for (var i = 0; i < recent.length; i++) {
      final c = recent[i];
      final word = sceneText('probe.${c.answer}');
      drawLabel(
        canvas,
        '${c.value}  →  $word',
        Offset(50, 73 + i * 6),
        size: 3.8 - i * 0.3,
        color: i == 0 ? Palette.ink : Palette.inkSoft,
        weight: i == 0 ? FontWeight.w600 : FontWeight.w500,
      );
    }
    if (bisect) {
      fitLabel(
        canvas,
        sceneText('probe.bisect_note'),
        const Offset(50, 95),
        100 - 2 * margin,
        size: 3,
        color: Palette.inkSoft,
        weight: FontWeight.w500,
      );
    }
  }
}
