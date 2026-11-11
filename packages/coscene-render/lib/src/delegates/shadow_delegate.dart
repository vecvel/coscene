import 'dart:math' as math;
import 'dart:ui';

import 'package:coscene_core/coscene_core.dart';

import '../draw.dart';
import '../palette.dart';
import '../scene_delegate.dart';

enum _Grab { lamp, board }

/// The lamp on its rail, the board, and the shadow the board throws.
class ShadowDelegate extends SceneDelegate<ShadowScene> {
  ShadowDelegate(super.scene);

  static const double _originX = 6;
  static const double _groundY = 84;
  static const double _scale = 0.88;
  static const double _bandDepth = 6;
  static const double _paintDepth = 3.2;

  _Grab? _drag;
  double _grabOffset = 0;

  /// World (x along the ground, h above it) to scene units.
  Offset _at(double x, double h) => Offset(_originX + x * _scale, _groundY - h * _scale);

  double _worldX(Offset p) => (p.dx - _originX) / _scale;
  double _worldH(Offset p) => (_groundY - p.dy) / _scale;

  Offset get _lamp => _at(scene.lampX.value, scene.lampHeight.value);
  Offset get _boardLeft => _at(scene.boardX.value, scene.boardHeight);
  Offset get _boardRight => _at(scene.boardX.value + scene.boardWidth, scene.boardHeight);

  /// A strip of the ground band between two world positions, kept on the ground.
  Rect _strip(double from, double to) {
    final a = _at(math.min(from, to).clamp(0.0, 100.0), 0);
    final b = _at(math.max(from, to).clamp(0.0, 100.0), 0);
    return Rect.fromLTRB(a.dx, _groundY, b.dx, _groundY + _paintDepth);
  }

  @override
  bool onDown(Offset p) {
    final lampMoves = !scene.lampX.isFixed || !scene.lampHeight.isFixed;
    final a = _boardLeft, b = _boardRight;
    final toBoard = pointSegmentDistance(Vec2(p.dx, p.dy), Vec2(a.dx, a.dy), Vec2(b.dx, b.dy));
    if (lampMoves && (p - _lamp).distance <= 10) {
      _drag = _Grab.lamp;
    } else if (!scene.boardX.isFixed && toBoard <= 8) {
      _drag = _Grab.board;
      _grabOffset = _worldX(p) - scene.boardX.value;
    } else {
      return false;
    }
    feedback(SceneFeedback.lift);
    return true;
  }

  @override
  void onMove(Offset p) {
    final drag = _drag;
    if (drag == null) return;
    var moved = false;
    if (drag == _Grab.lamp) {
      moved = scene.lampX.moveTo(_worldX(p));
      if (!scene.lampHeight.isFixed && scene.lampHeight.moveTo(_worldH(p))) moved = true;
    } else {
      moved = scene.boardX.moveTo(_worldX(p) - _grabOffset);
    }
    if (moved) {
      feedback(SceneFeedback.tick);
      changed();
    }
  }

  @override
  void onUp(Offset p) => _drag = null;

  @override
  void sync() => _drag = null;

  /// A rail between two world points, with a tick per step when there are few.
  void _rail(Canvas canvas, Adjustable control, Offset Function(double value) place, Offset tick) {
    if (control.isFixed) return;
    canvas.drawLine(place(control.min), place(control.max), line(Palette.ink, 0.6));
    if (control.count > 20) return;
    final paint = line(Palette.ink, 0.6, cap: StrokeCap.butt);
    for (var i = 0; i < control.count; i++) {
      final c = place(control.valueAt(i));
      canvas.drawLine(c - tick, c + tick, paint);
    }
  }

  /// The shadow of the last failed try, outlined on the ground band.
  void _ghost(Canvas canvas, Object? steps) {
    if (steps is! List || steps.length < 3) return;
    final lampX = steps[0], lampHeight = steps[1], boardX = steps[2];
    if (lampX is! int || lampHeight is! int || boardX is! int) return;
    final lx = scene.lampX.valueAt(lampX);
    final lh = scene.lampHeight.valueAt(lampHeight);
    final bx = scene.boardX.valueAt(boardX);
    if (lh <= scene.boardHeight) return;
    double project(double x) => lx + (x - lx) * lh / (lh - scene.boardHeight);
    final rect = _strip(project(bx), project(bx + scene.boardWidth));
    if (rect.width > 0) canvas.drawRect(rect.deflate(0.25), line(faint(Palette.ink, 0.35), 0.5));
  }

  /// The lit lamp's shadow: the dark wedge, its two edge rays and the ground mark.
  void _light(Canvas canvas, double light, bool solved) {
    final lamp = _lamp, left = _boardLeft, right = _boardRight;
    final shadow = scene.shadow;
    final from = _at(shadow.from, 0), to = _at(shadow.to, 0);

    // Anything thrown past the ends of the ground is cut off there.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(_at(0, 0).dx, -200, _at(100, 0).dx, 300));
    canvas.drawPath(
      Path()
        ..moveTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..lineTo(to.dx, to.dy)
        ..lineTo(from.dx, from.dy)
        ..close(),
      fill(faint(Palette.ink, 0.16 * light)),
    );
    final ray = line(faint(Palette.mustard, light), 0.5);
    canvas.drawLine(lamp, from, ray);
    canvas.drawLine(lamp, to, ray);
    canvas.restore();

    final mark = _strip(shadow.from, shadow.to);
    if (mark.width > 0) canvas.drawRect(mark, fill(faint(solved ? Palette.teal : Palette.ink, light)));
  }

  @override
  void paint(Canvas canvas, PaintContext ctx) {
    final solved = ctx.finished && ctx.outcome!.success;
    final groundLeft = _at(0, 0), groundRight = _at(100, 0);

    // Ground band and the painted patch the shadow has to cover.
    canvas.drawRect(Rect.fromLTRB(groundLeft.dx, _groundY, groundRight.dx, _groundY + _bandDepth), fill(Palette.stone));
    canvas.drawRect(_strip(scene.targetFrom, scene.targetTo), fill(solved ? Palette.teal : Palette.mustard));

    // Nothing is lit until the player submits.
    if (ctx.playing) {
      _light(canvas, ctx.track('light').clamp(0.0, 1.0), solved);
    } else {
      _ghost(canvas, ctx.ghost?['steps']);
    }
    canvas.drawLine(groundLeft, groundRight, line(Palette.ink, 1.2));

    // Rails the lamp rides on, and the board's travel.
    final lampX = scene.lampX.value, lampHeight = scene.lampHeight.value;
    _rail(canvas, scene.lampX, (v) => _at(v, lampHeight), const Offset(0, 0.6));
    _rail(canvas, scene.lampHeight, (v) => _at(lampX, v), const Offset(0.6, 0));
    if (!scene.boardX.isFixed) {
      drawDashed(
        canvas,
        _at(scene.boardX.min, scene.boardHeight),
        _at(scene.boardX.max + scene.boardWidth, scene.boardHeight),
        line(Palette.stone, 0.7),
      );
    }

    // Board.
    canvas.drawLine(_boardLeft, _boardRight, line(Palette.ink, 2.4, cap: StrokeCap.butt));

    // Lamp: stone while off, mustard once it is switched on.
    final lamp = _lamp;
    canvas.drawCircle(lamp, 3, fill(ctx.playing ? Palette.mustard : Palette.stone));
    canvas.drawLine(lamp + const Offset(-1.8, -3), lamp + const Offset(1.8, -3), line(Palette.ink, 1.4));
  }
}
