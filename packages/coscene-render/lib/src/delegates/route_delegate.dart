import 'dart:math' as math;
import 'dart:ui';

import 'package:coscene_core/coscene_core.dart';

import '../draw.dart';
import '../palette.dart';
import '../scene_delegate.dart';
import 'kit.dart';

/// A grid to cross. Drag or tap through neighbouring cells to draw a path;
/// going back over the path takes steps back.
class RouteDelegate extends SceneDelegate<RouteScene> {
  RouteDelegate(super.scene);

  double get _cell => 92 / math.max(scene.cols, scene.rows);
  Offset get _origin => Offset(50 - scene.cols * _cell / 2, 4);

  @override
  Size get logicalSize => Size(100, 8 + scene.rows * _cell + 10);

  Rect _rect(int i) =>
      Rect.fromLTWH(_origin.dx + (i % scene.cols) * _cell, _origin.dy + (i ~/ scene.cols) * _cell, _cell, _cell);

  int? _cellAt(Offset p) {
    final c = ((p.dx - _origin.dx) / _cell).floor(), r = ((p.dy - _origin.dy) / _cell).floor();
    if (c < 0 || r < 0 || c >= scene.cols || r >= scene.rows) return null;
    return r * scene.cols + c;
  }

  void _step(int? cell) {
    if (cell == null || cell == scene.path.last) return;
    if (scene.stepTo(cell)) {
      feedback(SceneFeedback.tick);
      changed();
    }
  }

  @override
  bool onDown(Offset p) {
    final cell = _cellAt(p);
    if (cell == null) return false;
    _step(cell);
    return true;
  }

  @override
  void onMove(Offset p) => _step(_cellAt(p));

  @override
  void paint(Canvas canvas, PaintContext ctx) {
    final weighted = scene.cells.any((c) => c > 1);
    final won = ctx.finished && (ctx.outcome?.success ?? false);
    final board = Rect.fromLTWH(_origin.dx, _origin.dy, scene.cols * _cell, scene.rows * _cell);
    final cells = cellGrid(
      canvas,
      board,
      scene.cols,
      rows: scene.rows,
      fillOf: (i) =>
          scene.cells[i] < 0 ? Palette.ink : (scene.path.contains(i) ? (won ? Palette.tealTint : peach) : null),
    );
    if (weighted) {
      for (var i = 0; i < cells.length; i++) {
        if (scene.cells[i] < 0 || i == scene.start || i == scene.goal) continue;
        fitLabel(
          canvas,
          '${scene.cells[i]}',
          cells[i].center,
          cells[i].width - 2,
          size: math.min(4.2, _cell * 0.34),
          color: Palette.inkSoft,
          weight: FontWeight.w500,
        );
      }
    }
    // The path as a line through cell centres; during playback it is walked.
    final walked = ctx.playing ? ctx.track('walk', orElse: scene.path.length - 1.0) : scene.path.length - 1.0;
    final pts = [for (final c in scene.path) _rect(c).center];
    final stroke = line(won ? Palette.teal : Palette.orange, math.max(1.0, _cell * 0.16));
    for (var i = 1; i < pts.length; i++) {
      if (i - 1 > walked) break;
      final t = (walked - (i - 1)).clamp(0.0, 1.0);
      canvas.drawLine(pts[i - 1], Offset.lerp(pts[i - 1], pts[i], t)!, stroke);
    }
    canvas.drawCircle(_rect(scene.start).center, _cell * 0.28, fill(Palette.orange));
    canvas.drawCircle(_rect(scene.goal).center, _cell * 0.3, line(Palette.teal, math.max(0.8, _cell * 0.1)));
    final bottom = _origin.dy + scene.rows * _cell + 6;
    final label = weighted ? '${scene.cost}' : '${scene.path.length - 1}';
    drawLabel(
      canvas,
      '${sceneText(weighted ? 'route.cost' : 'route.steps')}  $label',
      Offset(50, bottom),
      size: 4,
      weight: FontWeight.w500,
    );
  }
}
