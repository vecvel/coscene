import 'dart:math' as math;
import 'dart:ui';

import 'package:coscene_core/coscene_core.dart';

import '../draw.dart';
import '../palette.dart';
import '../scene_delegate.dart';

/// A ship's hold and the crates waiting on the dock. Drag crates aboard,
/// tap one to turn it.
class CargoDelegate extends SceneDelegate<CargoScene> {
  CargoDelegate(super.scene);

  @override
  Size get logicalSize => const Size(100, 108);

  int? _drag;
  Offset _dragPos = Offset.zero;
  Offset _grab = Offset.zero;
  (int, int, bool)? _dragHome;

  double get _cell => math.min(math.min(84 / scene.cols, 40 / scene.rows), 15);

  Rect get _grid {
    final c = _cell;
    return Rect.fromLTWH(50 - scene.cols * c / 2, 8, scene.cols * c, scene.rows * c);
  }

  Rect _cells(int col, int row, int w, int h) {
    final g = _grid, c = _cell;
    return Rect.fromLTWH(g.left + col * c, g.top + row * c, w * c, h * c);
  }

  /// Where every waiting crate sits on the dock, by piece index.
  Map<int, Rect> _dock() {
    final d = _cell * 0.5;
    final out = <int, Rect>{};
    var x = 6.0, y = _grid.bottom + 16, rowHeight = 0.0;
    for (var i = 0; i < scene.pieces.length; i++) {
      final p = scene.pieces[i];
      if (p.loaded) continue;
      final w = p.width * d, h = p.height * d;
      if (x + w > 94 && x > 6) {
        x = 6;
        y += rowHeight + 2.5;
        rowHeight = 0;
      }
      out[i] = Rect.fromLTWH(x, y, w, h);
      x += w + 3;
      rowHeight = math.max(rowHeight, h);
    }
    return out;
  }

  /// Top-left cell for the dragged crate when its centre is at [center].
  (int, int) _dropCell(CargoPiece piece, Offset center) {
    final g = _grid, c = _cell;
    return (((center.dx - g.left) / c - piece.width / 2).round(), ((center.dy - g.top) / c - piece.height / 2).round());
  }

  int? _dockHit(Offset p) {
    for (final e in _dock().entries) {
      if (e.key != _drag && e.value.inflate(3).contains(p)) return e.key;
    }
    return null;
  }

  int? _holdHit(Offset p) {
    final g = _grid, c = _cell;
    if (!g.contains(p)) return null;
    return scene.pieceAt(((p.dx - g.left) / c).floor(), ((p.dy - g.top) / c).floor());
  }

  @override
  bool onDown(Offset p) {
    final dock = _dockHit(p);
    final hit = dock ?? _holdHit(p);
    if (hit == null) return false;
    final piece = scene.pieces[hit];
    if (dock == null) {
      _dragHome = (piece.col!, piece.row!, piece.rotated);
      _grab = p - _cells(piece.col!, piece.row!, piece.width, piece.height).center;
      scene.unload(hit);
    } else {
      _dragHome = null;
      _grab = Offset.zero;
    }
    _drag = hit;
    _dragPos = p;
    feedback(SceneFeedback.lift);
    return true;
  }

  @override
  void onMove(Offset p) => _dragPos = p;

  @override
  void onUp(Offset p) {
    final i = _drag;
    if (i == null) return;
    _drag = null;
    final piece = scene.pieces[i];
    final home = _dragHome;
    final (col, row) = _dropCell(piece, p - _grab);
    if (scene.place(i, col, row, rotated: piece.rotated)) {
      if (home == null || home.$1 != col || home.$2 != row) {
        feedback(SceneFeedback.snap);
        changed();
      }
    } else if (_grid.inflate(_cell).contains(p)) {
      feedback(SceneFeedback.reject);
      if (home != null) scene.place(i, home.$1, home.$2, rotated: home.$3);
    } else if (home != null) {
      feedback(SceneFeedback.tick);
      changed();
    }
  }

  @override
  void onTap(Offset p) {
    final dock = _dockHit(p);
    if (dock != null) {
      final piece = scene.pieces[dock];
      if (piece.w == piece.h) return;
      piece.rotated = !piece.rotated;
      feedback(SceneFeedback.tick);
      changed();
      return;
    }
    final i = _holdHit(p);
    if (i == null) return;
    final piece = scene.pieces[i];
    if (piece.w == piece.h) return;
    final col = piece.col!, row = piece.row!, was = piece.rotated;
    scene.unload(i);
    if (scene.place(i, col, row, rotated: !was)) {
      feedback(SceneFeedback.snap);
      changed();
    } else {
      scene.place(i, col, row, rotated: was);
      feedback(SceneFeedback.reject);
    }
  }

  void _crate(Canvas canvas, Rect rect, CargoPiece piece) {
    final shape = RRect.fromRectAndRadius(rect.deflate(0.5), const Radius.circular(1.2));
    if (piece.heavy) {
      canvas.drawRRect(shape, fill(Palette.slate));
      drawPips(canvas, rect.deflate(math.min(rect.width, rect.height) * 0.25), 3, Palette.cream);
    } else {
      canvas.drawRRect(shape, fill(Palette.mustard));
      canvas.drawRRect(shape, line(Palette.ink, 0.5));
    }
  }

  @override
  void paint(Canvas canvas, PaintContext ctx) {
    final g = _grid, c = _cell;

    // The ship leans and sails as one piece.
    canvas.save();
    final pivot = g.bottomCenter;
    canvas.translate(ctx.track('sail') * 70 + ctx.track('shake') * 0.5 + pivot.dx, pivot.dy);
    canvas.rotate(ctx.track('list'));
    canvas.translate(-pivot.dx, -pivot.dy);

    final left = g.left - 4, right = g.right + 4, top = g.top - 2, bottom = g.bottom + 5;
    canvas.drawPath(
      Path()
        ..moveTo(left, top)
        ..lineTo(right, top)
        ..lineTo(right, bottom - 6)
        ..lineTo(right - 6, bottom)
        ..lineTo(left + 6, bottom)
        ..lineTo(left, bottom - 6)
        ..close(),
      fill(Palette.ink),
    );

    for (var r = 0; r < scene.rows; r++) {
      for (var col = 0; col < scene.cols; col++) {
        final cell = _cells(col, r, 1, 1);
        if (scene.blocked.contains(r * scene.cols + col)) {
          canvas.drawRect(cell, fill(Palette.stone));
          final hatch = line(Palette.ink, 0.5);
          canvas.drawLine(cell.topLeft, cell.bottomRight, hatch);
          canvas.drawLine(cell.topRight, cell.bottomLeft, hatch);
        } else {
          canvas.drawRect(cell, fill(Palette.cream));
        }
        canvas.drawRect(cell, line(Palette.stone, 0.4));
      }
    }

    // Last failed loading, as outlines.
    final ghost = ctx.ghost?['pieces'];
    if (ghost is List && !ctx.playing) {
      for (var i = 0; i < scene.pieces.length && i < ghost.length; i++) {
        final was = ghost[i];
        if (was is! List) continue;
        final p = scene.pieces[i];
        final rotated = was[2] == 1;
        if (p.col == was[0] && p.row == was[1] && p.rotated == rotated) continue;
        final rect = _cells(was[0] as int, was[1] as int, rotated ? p.h : p.w, rotated ? p.w : p.h);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(1.2)),
          line(faint(Palette.ink, 0.3), 0.5),
        );
      }
    }

    for (final p in scene.pieces) {
      if (p.loaded) _crate(canvas, _cells(p.col!, p.row!, p.width, p.height), p);
    }

    // Where the dragged crate would land.
    final drag = _drag;
    if (drag != null) {
      final piece = scene.pieces[drag];
      final (col, row) = _dropCell(piece, _dragPos - _grab);
      if (scene.canPlace(drag, col, row, rotated: piece.rotated)) {
        canvas.drawRect(_cells(col, row, piece.width, piece.height).deflate(0.5), line(Palette.orange, 1));
      }
    }
    canvas.restore();

    // Water in front of the hull, so the ship sits in it.
    canvas.drawRect(Rect.fromLTWH(0, g.bottom + 3.5, 100, 5.5), fill(Palette.slate));

    // Dock.
    final leftBehind = ctx.finished && ctx.outcome!.kind == 'left_behind';
    for (final e in _dock().entries) {
      if (e.key == drag) continue;
      _crate(canvas, e.value, scene.pieces[e.key]);
      if (leftBehind) canvas.drawRect(e.value.inflate(1), line(Palette.coral, 1));
    }

    if (drag != null) {
      final piece = scene.pieces[drag];
      _crate(
        canvas,
        Rect.fromCenter(center: _dragPos - _grab, width: piece.width * c, height: piece.height * c),
        piece,
      );
    }
  }
}
