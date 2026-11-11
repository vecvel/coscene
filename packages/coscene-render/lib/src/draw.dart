import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'palette.dart';

/// Small drawing helpers shared by every scene. All sizes are in scene
/// units; the view scales the canvas, so nothing here knows about pixels.

Paint fill(Color color) => Paint()
  ..color = color
  ..style = PaintingStyle.fill
  ..isAntiAlias = true;

Paint line(Color color, double width, {StrokeCap cap = StrokeCap.round}) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = cap
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;

/// A colour at part strength, for ghosts and quiet hints.
Color faint(Color color, [double opacity = 0.28]) => color.withValues(alpha: opacity);

/// Text centred on [center].
void drawLabel(
  Canvas canvas,
  String text,
  Offset center, {
  double size = 5,
  Color color = Palette.ink,
  FontWeight weight = FontWeight.w600,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  painter.dispose();
}

void drawDashed(Canvas canvas, Offset a, Offset b, Paint paint, {double dash = 2, double gap = 1.6}) {
  final total = (b - a).distance;
  if (total == 0) return;
  final dir = (b - a) / total;
  for (var d = 0.0; d < total; d += dash + gap) {
    canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), paint);
  }
}

/// Weight shown as dots, laid out in a tidy block inside [box].
void drawPips(Canvas canvas, Rect box, int count, Color color) {
  if (count <= 0) return;
  final cols = count <= 3 ? count : (count == 4 ? 2 : 3);
  final rows = (count / cols).ceil();
  final r = math.min(box.width / (cols * 3.2), box.height / (rows * 3.2)).clamp(0.3, 1.5);
  final gapX = box.width / cols, gapY = box.height / rows;
  final paint = fill(color);
  for (var i = 0; i < count; i++) {
    final row = i ~/ cols, col = i % cols;
    final inRow = row == rows - 1 ? count - row * cols : cols;
    final startX = box.center.dx - (inRow - 1) * gapX / 2;
    canvas.drawCircle(Offset(startX + col * gapX, box.top + gapY * (row + 0.5)), r, paint);
  }
}

/// Each named colour also has its own shape, so colour is never the only cue.
void drawGlyph(Canvas canvas, String colorId, Offset c, double r, Paint paint) {
  switch (colorId) {
    case 'coral':
      canvas.drawCircle(c, r, paint);
    case 'teal':
      canvas.drawRect(Rect.fromCircle(center: c, radius: r * 0.86), paint);
    case 'mustard':
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - r)
          ..lineTo(c.dx + r, c.dy + r * 0.8)
          ..lineTo(c.dx - r, c.dy + r * 0.8)
          ..close(),
        paint,
      );
    default:
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - r)
          ..lineTo(c.dx + r, c.dy)
          ..lineTo(c.dx, c.dy + r)
          ..lineTo(c.dx - r, c.dy)
          ..close(),
        paint,
      );
  }
}

/// An arrow head at [tip], pointing along [direction] (radians).
void drawArrowHead(Canvas canvas, Offset tip, double direction, double size, Paint paint) {
  final back = Offset(math.cos(direction), math.sin(direction)) * size;
  final side = Offset(-back.dy, back.dx) * 0.55;
  canvas.drawPath(
    Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - back.dx + side.dx, tip.dy - back.dy + side.dy)
      ..lineTo(tip.dx - back.dx - side.dx, tip.dy - back.dy - side.dy)
      ..close(),
    paint,
  );
}

/// Smooth 0-1 ease used for small local motions.
double easeOut(double t) {
  final x = t.clamp(0.0, 1.0);
  return 1 - (1 - x) * (1 - x) * (1 - x);
}
