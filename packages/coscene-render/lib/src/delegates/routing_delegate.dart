import 'dart:math' as math;
import 'dart:ui';

import 'package:coscene_core/coscene_core.dart';

import '../draw.dart';
import '../palette.dart';
import '../scene_delegate.dart';

/// Belts carrying coloured parcels through junctions into bins.
class RoutingDelegate extends SceneDelegate<RoutingScene> {
  RoutingDelegate(super.scene);

  Offset _at(String id) {
    final v = scene.nodes[id]!.position;
    return Offset(v.x, v.y);
  }

  @override
  void onTap(Offset p) {
    RouteNode? hit;
    var best = 10.0;
    for (final n in scene.junctions) {
      final d = (p - _at(n.id)).distance;
      if (d < best) {
        best = d;
        hit = n;
      }
    }
    if (hit == null) return;
    if (scene.cycle(hit.id)) {
      feedback(SceneFeedback.tick);
      changed();
    } else {
      feedback(SceneFeedback.reject);
    }
  }

  void _parcel(Canvas canvas, Offset c, String color) {
    canvas.drawCircle(c, 2.7, fill(Palette.cream));
    canvas.drawCircle(c, 2.7, line(Palette.ink, 0.5));
    drawGlyph(canvas, color, c, 1.7, fill(Palette.named(color)));
  }

  void _arrow(Canvas canvas, Offset center, Offset toward, Color color) {
    final delta = toward - center;
    final dir = delta / delta.distance;
    final tip = center + dir * 4;
    canvas.drawLine(center - dir * 2.4, tip - dir * 1.2, line(color, 1.5));
    drawArrowHead(canvas, tip, math.atan2(dir.dy, dir.dx), 3, fill(color));
  }

  @override
  void paint(Canvas canvas, PaintContext ctx) {
    // Belts.
    for (final n in scene.nodes.values) {
      for (final id in [n.next, n.left, n.right]) {
        if (id == null) continue;
        canvas.drawLine(_at(n.id), _at(id), line(Palette.stone, 4.2));
        canvas.drawLine(_at(n.id), _at(id), line(faint(Palette.ink, 0.25), 0.4));
      }
    }

    // Bins.
    for (final n in scene.nodes.values.where((n) => n.kind == RouteKind.bin)) {
      final c = _at(n.id);
      final color = Palette.named(n.accepts!);
      final box = Rect.fromLTWH(c.dx - 6.5, c.dy - 4, 13, 9);
      canvas.drawRect(box, fill(faint(color, 0.25)));
      final edge = line(Palette.ink, 1, cap: StrokeCap.square);
      canvas.drawLine(box.topLeft, box.bottomLeft, edge);
      canvas.drawLine(box.bottomLeft, box.bottomRight, edge);
      canvas.drawLine(box.bottomRight, box.topRight, edge);
      drawGlyph(canvas, n.accepts!, Offset(c.dx, math.min(c.dy + 7.6, 97.8)), 1.8, fill(color));
    }

    // Source funnel.
    final s = _at(scene.source.id);
    canvas.drawPath(
      Path()
        ..moveTo(s.dx - 6, s.dy - 4)
        ..lineTo(s.dx + 6, s.dy - 4)
        ..lineTo(s.dx + 3, s.dy + 2)
        ..lineTo(s.dx - 3, s.dy + 2)
        ..close(),
      fill(Palette.ink),
    );

    // Junctions.
    for (final n in scene.junctions) {
      final c = _at(n.id);
      final ring = n.fixed ? Palette.stone : Palette.ink;
      canvas.drawCircle(c, 6.5, fill(n.fixed ? Palette.sand : Palette.white));
      if (n.kind == RouteKind.filter) {
        final colorId = scene.colors[n.state];
        final color = Palette.named(colorId);
        canvas.drawCircle(c, 6.5, fill(faint(color, 0.3)));
        drawGlyph(canvas, colorId, c, 2.6, fill(color));
        final toLeft = _at(n.left!) - c;
        final dir = toLeft / toLeft.distance;
        drawArrowHead(canvas, c + dir * 10.4, math.atan2(dir.dy, dir.dx), 2.8, fill(Palette.ink));
      } else {
        var state = n.state;
        if (n.kind == RouteKind.flip) {
          state = ctx.track('flip:${n.id}', orElse: n.state.toDouble()).round();
          canvas.drawCircle(c, 8.2, line(Palette.ink, 0.6));
        }
        _arrow(canvas, c, _at(state == 0 ? n.left! : n.right!), Palette.ink);
      }
      canvas.drawCircle(c, 6.5, line(ring, 1.2));
    }

    // Parcels: waiting in line, travelling, or resting in a bin.
    final trips = ctx.playing ? scene.run() : null;
    final leftward = s.dx + 9 + scene.items.length * 6.5 > 96;
    final resting = <String, int>{};
    var queued = 0;
    for (var k = 0; k < scene.items.length; k++) {
      final color = scene.items[k];
      if (trips == null || ctx.track('on$k') < 0.5) {
        final step = 9 + queued++ * 6.5;
        _parcel(canvas, Offset(leftward ? s.dx - step : s.dx + step, s.dy - 1), color);
        continue;
      }
      var pos = Offset(ctx.track('x$k'), ctx.track('y$k'));
      final bin = _at(trips[k].bin);
      final arrived = (pos - bin).distance < 0.5;
      if (arrived) {
        final below = resting.update(trips[k].bin, (v) => v + 1, ifAbsent: () => 1) - 1;
        pos = Offset(bin.dx, bin.dy + 1.6 - below * 5.6);
      }
      _parcel(canvas, pos, color);
      if (ctx.finished && arrived && !trips[k].correct) {
        final x = line(Palette.ink, 0.9);
        canvas.drawLine(pos + const Offset(-2.2, -2.2), pos + const Offset(2.2, 2.2), x);
        canvas.drawLine(pos + const Offset(2.2, -2.2), pos + const Offset(-2.2, 2.2), x);
      }
    }
  }
}
