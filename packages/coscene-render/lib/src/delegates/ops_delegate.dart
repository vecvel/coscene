import 'dart:math' as math;
import 'dart:ui';

import 'package:coscene_core/coscene_core.dart';

import '../draw.dart';
import '../palette.dart';
import '../scene_delegate.dart';
import 'kit.dart';

/// Moves made one at a time: pushing and popping a stack, swapping tiles
/// into order, or putting tasks in a working order.
class OpsDelegate extends SceneDelegate<OpsScene> {
  OpsDelegate(super.scene);

  final List<Hit> _hits = [];
  int? _held;

  @override
  Size get logicalSize => switch (scene.mode) {
    'stack' => const Size(100, 84),
    'swap' => const Size(100, 36),
    _ => const Size(100, 92),
  };

  void _move(int m) {
    if (scene.apply(m)) {
      feedback(SceneFeedback.snap);
      changed();
    } else {
      feedback(SceneFeedback.reject);
    }
  }

  @override
  void onTap(Offset p) {
    if (!tapHits(_hits, p) && _held != null) {
      _held = null;
      changed();
    }
  }

  @override
  void paint(Canvas canvas, PaintContext ctx) {
    _hits.clear();
    final won = ctx.finished && (ctx.outcome?.success ?? false);
    canvas.save();
    canvas.translate(ctx.finished ? 0 : shake(ctx.track('shake')), 0);
    switch (scene.mode) {
      case 'stack':
        _stack(canvas, won);
      case 'swap':
        _swap(canvas, won);
      default:
        _order(canvas, won);
    }
    canvas.restore();
  }

  /// Values in joined strips of up to [perRow] cells, left-aligned at [x].
  void _strips(
    Canvas canvas,
    List<Object> values,
    double x,
    double y, {
    int perRow = 3,
    double w = 9,
    Color? Function(int i)? fillOf,
    Color Function(int i)? textOf,
  }) {
    for (var from = 0; from < values.length; from += perRow) {
      final count = math.min(perRow, values.length - from);
      final top = y + (from ~/ perRow) * (w + 2);
      final cells = cellGrid(
        canvas,
        Rect.fromLTWH(x, top, count * w, w),
        count,
        fillOf: fillOf == null ? null : (k) => fillOf(from + k),
      );
      for (var k = 0; k < count; k++) {
        cellText(canvas, '${values[from + k]}', cells[k], color: textOf?.call(from + k) ?? Palette.ink);
      }
    }
  }

  void _stack(Canvas canvas, bool won) {
    const s = 9.0;
    final n = scene.items.length;
    // The order to produce, along the top.
    final tw = cellWidth(n, max: 10);
    final tx = 50 - n * tw / 2;
    caption(canvas, sceneText('ops.target'), Offset(tx + 0.6, 2.4));
    final target = cellGrid(
      canvas,
      Rect.fromLTWH(tx, 5, n * tw, 10),
      n,
      fillOf: (i) => i < scene.output.length ? (won ? Palette.teal : Palette.tealTint) : null,
    );
    for (var i = 0; i < n; i++) {
      final done = i < scene.output.length;
      cellText(canvas, '${scene.target[i]}', target[i], color: done && won ? Palette.white : Palette.ink);
    }
    // Arriving items on the left, the stack in the middle, the output on the right.
    caption(canvas, sceneText('ops.in'), const Offset(margin + 0.6, 22));
    _strips(canvas, scene.items.sublist(scene.next), margin, 25);
    const well = Rect.fromLTWH(43, 21, 14, 44);
    final wall = line(Palette.ink, 0.7);
    canvas.drawLine(well.topLeft, well.bottomLeft, wall);
    canvas.drawLine(well.bottomLeft, well.bottomRight, wall);
    canvas.drawLine(well.bottomRight, well.topRight, wall);
    if (scene.cap > 0) {
      final capY = well.bottom - 1.4 - scene.cap * (s + 1.2);
      drawDashed(canvas, Offset(well.left, capY), Offset(well.right, capY), line(faint(Palette.coralDeep, 0.7), 0.35));
    }
    for (var i = 0; i < scene.stack.length; i++) {
      final r = Rect.fromLTWH(well.left + 1.6, well.bottom - 1.4 - (i + 1) * (s + 1.2) + 1.2, well.width - 3.2, s);
      tile(canvas, r, Palette.slate, radius: 1.8);
      cellText(canvas, '${scene.stack[i]}', r, color: Palette.white);
    }
    final outX = 100 - margin - 3 * s;
    caption(canvas, sceneText('ops.out'), Offset(outX + 0.6, 22));
    _strips(
      canvas,
      scene.output,
      outX,
      25,
      fillOf: (i) => scene.output[i] == scene.target[i] ? (won ? Palette.teal : Palette.tealTint) : wrongTint,
      textOf: (i) => won ? Palette.white : Palette.ink,
    );
    const push = Rect.fromLTWH(margin, 71, 44, 10), pop = Rect.fromLTWH(52, 71, 44, 10);
    button(canvas, push, sceneText('ops.push'), enabled: scene.canPush);
    button(canvas, pop, sceneText('ops.pop'), enabled: scene.canPop);
    _hits
      ..add(Hit(push, () => _move(0)))
      ..add(Hit(pop, () => _move(1)));
  }

  void _swap(Canvas canvas, bool won) {
    final n = scene.row.length;
    final w = cellWidth(n, max: 12);
    final rect = Rect.fromLTWH(50 - n * w / 2, 4, n * w, 12);
    final cells = cellGrid(canvas, rect, n, fillOf: (i) => won ? Palette.teal : (_held == i ? Palette.orange : null));
    for (var i = 0; i < n; i++) {
      cellText(canvas, '${scene.row[i]}', cells[i], color: won || _held == i ? Palette.white : Palette.ink);
      _hits.add(
        Hit(cells[i], () {
          final h = _held;
          if (h == null) {
            _held = i;
            feedback(SceneFeedback.tick);
            changed();
          } else if (h == i) {
            _held = null;
            changed();
          } else {
            _held = null;
            _move(math.min(h, i) * 16 + math.max(h, i));
          }
        }),
      );
    }
    // Swaps left, as dots.
    final used = scene.moves.length;
    final total = math.max(scene.budget, used);
    for (var i = 0; i < total; i++) {
      final c = Offset(50 + (i - (total - 1) / 2) * 4.4, rect.bottom + 9);
      final over = i >= scene.budget;
      canvas.drawCircle(c, 1.3, i < used ? fill(over ? Palette.coralDeep : Palette.ink) : line(Palette.stone, 0.5));
    }
  }

  void _order(Canvas canvas, bool won) {
    final n = scene.items.length;
    // Depth of each task: the longest chain of tasks before it.
    final depth = List<int>.filled(n, 0);
    for (var pass = 0; pass < n; pass++) {
      for (final (a, b) in scene.deps) {
        if (depth[b] < depth[a] + 1) depth[b] = depth[a] + 1;
      }
    }
    final levels = depth.reduce(math.max) + 1;
    final byLevel = [
      for (var l = 0; l < levels; l++)
        [
          for (var t = 0; t < n; t++)
            if (depth[t] == l) t,
        ],
    ];
    final at = <int, Offset>{};
    for (var l = 0; l < levels; l++) {
      final col = byLevel[l];
      for (var k = 0; k < col.length; k++) {
        at[col[k]] = Offset(10 + l * (80 / math.max(1, levels - 1)), 34 + (k - (col.length - 1) / 2) * 13);
      }
    }
    for (final (a, b) in scene.deps) {
      final p = at[a]!, q = at[b]!;
      final dir = (q - p) / (q - p).distance;
      canvas.drawLine(p + dir * 5.4, q - dir * 6.4, line(faint(Palette.ink, 0.45), 0.6));
      drawArrowHead(canvas, q - dir * 5.4, math.atan2(dir.dy, dir.dx), 2.2, fill(faint(Palette.ink, 0.6)));
    }
    for (var t = 0; t < n; t++) {
      final placed = scene.moves.indexOf(t);
      final r = Rect.fromCenter(center: at[t]!, width: 10, height: 10);
      tile(canvas, r, placed >= 0 ? (won ? Palette.teal : Palette.ink) : Palette.white, radius: 5);
      drawLabel(canvas, scene.labels[t], r.center, size: 4, color: placed >= 0 ? Palette.cream : Palette.ink);
      _hits.add(
        Hit(r, () {
          if (placed >= 0) {
            if (placed == scene.moves.length - 1) {
              scene.undo();
              feedback(SceneFeedback.tick);
              changed();
            } else {
              feedback(SceneFeedback.reject);
            }
          } else {
            _move(t);
          }
        }),
      );
    }
    // The order so far.
    final w = cellWidth(n, max: 10);
    final slots = cellGrid(
      canvas,
      Rect.fromLTWH(50 - n * w / 2, 78, n * w, 10),
      n,
      fillOf: (i) => won && i < scene.moves.length ? Palette.teal : null,
    );
    for (var i = 0; i < n; i++) {
      if (i < scene.moves.length) {
        cellText(canvas, scene.labels[scene.moves[i]], slots[i], color: won ? Palette.white : Palette.ink);
      } else {
        drawLabel(
          canvas,
          '${i + 1}',
          slots[i].center,
          size: 2.8,
          color: Palette.stone,
          weight: FontWeight.w500,
          mono: true,
        );
      }
    }
  }
}
