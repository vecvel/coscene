import 'dart:math' as math;
import 'dart:ui';

import 'package:coscene_core/coscene_core.dart';

import '../draw.dart';
import '../palette.dart';
import '../scene_delegate.dart';
import 'kit.dart';

/// Tiles to select. Rows of numbers, place values that light up, meetings on
/// a time line, or items with a weight and a value.
class PickDelegate extends SceneDelegate<PickScene> {
  PickDelegate(super.scene);

  final List<Hit> _hits = [];

  int get _perRow => scene.tiles.length <= 8 ? scene.tiles.length : (scene.tiles.length / 2).ceil();
  int get _rows => (scene.tiles.length / _perRow).ceil();
  double get _rowH => scene.rule == 'window' ? 12.5 : 11;

  @override
  Size get logicalSize => switch (scene.layout) {
    'bars' => Size(100, 14 + scene.tiles.length * 9.0),
    'items' => const Size(100, 80),
    'bits' => const Size(100, 44),
    _ => Size(100, 6 + _rows * _rowH + (_rows - 1) * 4),
  };

  void _toggle(int i) {
    scene.toggle(i);
    feedback(scene.picked.contains(i) ? SceneFeedback.snap : SceneFeedback.tick);
    changed();
  }

  @override
  void onTap(Offset p) => tapHits(_hits, p);

  @override
  void paint(Canvas canvas, PaintContext ctx) {
    _hits.clear();
    final dx = ctx.finished ? 0.0 : shake(ctx.track('shake'));
    final judged = ctx.finished && ctx.outcome != null;
    final won = judged && ctx.outcome!.success;
    canvas.save();
    canvas.translate(dx, 0);
    switch (scene.layout) {
      case 'bits':
        _bits(canvas, won);
      case 'bars':
        _bars(canvas, won);
      case 'items':
        _items(canvas, won);
      default:
        _row(canvas, won);
    }
    canvas.restore();
  }

  Color _on(bool won) => won ? Palette.teal : Palette.orange;

  void _row(Canvas canvas, bool won) {
    final n = scene.tiles.length;
    final w = cellWidth(_perRow);
    for (var row = 0; row < _rows; row++) {
      final from = row * _perRow;
      final count = math.min(_perRow, n - from);
      final rect = Rect.fromLTWH(50 - count * w / 2, 3 + row * (_rowH + 4), count * w, _rowH);
      final cells = cellGrid(canvas, rect, count, fillOf: (k) => scene.picked.contains(from + k) ? _on(won) : null);
      for (var k = 0; k < count; k++) {
        final i = from + k;
        final on = scene.picked.contains(i);
        cellText(
          canvas,
          '${scene.tiles[i].v}',
          cells[k],
          color: on ? Palette.white : Palette.ink,
          index: scene.rule == 'window' ? '$i' : null,
          indexColor: on ? Palette.white : null,
        );
        _hits.add(Hit(cells[k], () => _toggle(i)));
      }
    }
  }

  void _bits(Canvas canvas, bool won) {
    final n = scene.tiles.length;
    final w = cellWidth(n, max: 12);
    final rect = Rect.fromLTWH(50 - n * w / 2, 4, n * w, w * 1.15);
    final cells = cellGrid(canvas, rect, n, fillOf: (i) => scene.picked.contains(i) ? _on(won) : null);
    for (var i = 0; i < n; i++) {
      final on = scene.picked.contains(i);
      cellText(canvas, on ? '1' : '0', cells[i], color: on ? Palette.white : Palette.stone);
      drawLabel(
        canvas,
        '${scene.tiles[i].v}',
        Offset(cells[i].center.dx, rect.bottom + 3.4),
        size: 3,
        color: Palette.inkSoft,
        weight: FontWeight.w500,
        mono: true,
      );
      _hits.add(Hit(cells[i], () => _toggle(i)));
    }
    drawLabel(canvas, '= ${scene.total}', Offset(50, rect.bottom + 14), size: 7, weight: FontWeight.w600);
  }

  void _bars(Canvas canvas, bool won) {
    const left = 6.0, right = 94.0;
    final maxEnd = scene.tiles.map((t) => t.e).reduce(math.max).toDouble();
    double x(num t) => left + t / maxEnd * (right - left);
    for (var t = 0; t <= maxEnd; t += 2) {
      canvas.drawLine(
        Offset(x(t), 6),
        Offset(x(t), 10 + scene.tiles.length * 9.0),
        line(faint(Palette.ink, 0.08), 0.3),
      );
      drawLabel(
        canvas,
        '$t',
        Offset(x(t), 3.6),
        size: 2.8,
        color: Palette.inkSoft,
        weight: FontWeight.w500,
        mono: true,
      );
    }
    for (var i = 0; i < scene.tiles.length; i++) {
      final t = scene.tiles[i];
      final r = Rect.fromLTRB(x(t.s), 8 + i * 9.0, x(t.e), 14.6 + i * 9.0);
      final on = scene.picked.contains(i);
      tile(canvas, r, on ? _on(won) : Palette.white, radius: 1.6);
      fitLabel(
        canvas,
        '${t.s}–${t.e}',
        r.center,
        r.width - 2,
        size: 3.2,
        color: on ? Palette.white : Palette.ink,
        weight: FontWeight.w500,
      );
      _hits.add(Hit(Rect.fromLTRB(r.left, r.top - 1, math.max(r.right, r.left + 8), r.bottom + 1), () => _toggle(i)));
    }
  }

  void _items(Canvas canvas, bool won) {
    final n = scene.tiles.length;
    final perRow = n <= 4 ? n : (n / 2).ceil();
    const gap = 2.4;
    final w = (100 - 2 * margin - gap * (perRow - 1)) / perRow;
    for (var i = 0; i < n; i++) {
      final row = i ~/ perRow, col = i % perRow;
      final inRow = row == (n / perRow).ceil() - 1 ? n - row * perRow : perRow;
      final x0 = 50 - (inRow * w + (inRow - 1) * gap) / 2;
      final r = Rect.fromLTWH(x0 + col * (w + gap), 3 + row * 26.0, w, 23);
      final on = scene.picked.contains(i);
      final t = scene.tiles[i];
      tile(canvas, r, on ? _on(won) : Palette.white);
      final fg = on ? Palette.white : Palette.ink;
      drawLabel(canvas, '${t.v}', Offset(r.center.dx, r.top + 9), size: 5.6, color: fg, weight: FontWeight.w600);
      drawLabel(
        canvas,
        '${t.w} kg',
        Offset(r.center.dx, r.top + 16.5),
        size: 3.2,
        color: on ? Palette.white : Palette.inkSoft,
        weight: FontWeight.w500,
      );
      _hits.add(Hit(r, () => _toggle(i)));
    }
    // The load so far against the limit.
    const bar = Rect.fromLTWH(margin, 62, 100 - 2 * margin, 4.4);
    tile(canvas, bar, Palette.sand, radius: 2.2);
    final share = (scene.weight / math.max(1, scene.cap)).clamp(0.0, 1.0);
    if (share > 0) {
      tile(
        canvas,
        Rect.fromLTWH(bar.left, bar.top, bar.width * share, bar.height),
        scene.weight > scene.cap ? Palette.coralDeep : Palette.ink,
        radius: 2.2,
      );
    }
    drawLabel(canvas, '${scene.weight} / ${scene.cap} kg', const Offset(50, 73), size: 4, weight: FontWeight.w600);
  }
}
