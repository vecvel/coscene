import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'draw.dart';
import 'palette.dart';

/// Every icon in the game. All are drawn here in code, in one style: thick
/// outlines with rounded ends and corners, and a back arrow that curves.
/// The app ships no icon font and no icon files.
enum GameIcons { back, play, settings, hint, lock, notebook, reset, replay, share, star, sun, solved, open }

class GameIcon extends StatelessWidget {
  const GameIcon(this.icon, {super.key, this.size = 24, this.color = Palette.ink, this.fill});

  final GameIcons icon;
  final double size;

  /// Colour of the outline.
  final Color color;

  /// Optional colour inside closed shapes, used for earned stars.
  final Color? fill;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: GameIconPainter(icon, color, fill: fill),
  );
}

/// Draws one icon on a 24-unit grid, scaled to the space it is given.
class GameIconPainter extends CustomPainter {
  GameIconPainter(this.icon, this.color, {this.fill});

  final GameIcons icon;
  final Color color;
  final Color? fill;

  static const double _stroke = 2.4;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24);
    final outline = line(color, _stroke);

    void shape(Path path) {
      final inside = fill;
      if (inside != null) canvas.drawPath(path, Paint()..color = inside);
      canvas.drawPath(path, outline);
    }

    void stroke(Path path) => canvas.drawPath(path, outline);

    Path turnArrow() => Path()
      ..moveTo(18.1, 8.5)
      ..arcToPoint(const Offset(19, 12), radius: const Radius.circular(7), largeArc: true, clockwise: false)
      ..moveTo(18.6, 4.2)
      ..lineTo(18.6, 8.8)
      ..lineTo(14, 8.8);

    switch (icon) {
      case GameIcons.back:
        stroke(
          Path()
            ..moveTo(19, 13.5)
            ..quadraticBezierTo(12.5, 8, 6, 12)
            ..moveTo(10.5, 7)
            ..lineTo(5.5, 12)
            ..lineTo(11, 16.5),
        );
      case GameIcons.play:
        shape(
          Path()
            ..moveTo(8.5, 6)
            ..lineTo(18, 12)
            ..lineTo(8.5, 18)
            ..close(),
        );
      case GameIcons.settings:
        // Two sliders. Each track stops short of its knob, so the icon
        // needs no background colour to hide a line behind the knob.
        stroke(
          Path()
            ..moveTo(4, 8.5)
            ..lineTo(6.2, 8.5)
            ..moveTo(11.8, 8.5)
            ..lineTo(20, 8.5)
            ..moveTo(4, 15.5)
            ..lineTo(12.2, 15.5)
            ..moveTo(17.8, 15.5)
            ..lineTo(20, 15.5),
        );
        canvas.drawCircle(const Offset(9, 8.5), 2.6, outline);
        canvas.drawCircle(const Offset(15, 15.5), 2.6, outline);
      case GameIcons.hint:
        shape(
          Path()
            ..moveTo(8.6, 14.6)
            ..arcToPoint(const Offset(15.4, 14.6), radius: const Radius.circular(6), largeArc: true)
            ..lineTo(15.4, 17)
            ..lineTo(8.6, 17)
            ..close(),
        );
        canvas.drawLine(const Offset(10, 20.3), const Offset(14, 20.3), outline);
      case GameIcons.lock:
        shape(
          Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(5, 10.5, 14, 9.5), const Radius.circular(3))),
        );
        stroke(
          Path()
            ..moveTo(8.3, 10.5)
            ..lineTo(8.3, 8.2)
            ..arcToPoint(const Offset(15.7, 8.2), radius: const Radius.circular(3.7))
            ..lineTo(15.7, 10.5),
        );
        canvas.drawCircle(const Offset(12, 15.2), 1.3, Paint()..color = color);
      case GameIcons.notebook:
        shape(Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(5, 4, 14, 16), const Radius.circular(3))));
        stroke(
          Path()
            ..moveTo(9, 4)
            ..lineTo(9, 20)
            ..moveTo(12.5, 9)
            ..lineTo(15.5, 9)
            ..moveTo(12.5, 12.5)
            ..lineTo(15.5, 12.5),
        );
      case GameIcons.reset:
        stroke(turnArrow());
      case GameIcons.replay:
        canvas.translate(24, 0);
        canvas.scale(-1, 1);
        stroke(turnArrow());
      case GameIcons.share:
        // A paper plane with its fold line.
        stroke(
          Path()
            ..moveTo(20, 4)
            ..lineTo(3.8, 10.6)
            ..lineTo(10.4, 13.4)
            ..lineTo(13.2, 20)
            ..close()
            ..moveTo(10.4, 13.4)
            ..lineTo(20, 4),
        );
      case GameIcons.star:
        const points = [
          Offset(12, 3.6), Offset(14.5, 9), Offset(20.4, 9.7), Offset(16, 13.7), Offset(17.2, 19.6),
          Offset(12, 16.6), Offset(6.8, 19.6), Offset(8, 13.7), Offset(3.6, 9.7), Offset(9.5, 9), //
        ];
        shape(Path()..addPolygon(points, true));
      case GameIcons.sun:
        shape(Path()..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 4)));
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          canvas.drawCircle(const Offset(12, 12) + Offset(math.cos(a), math.sin(a)) * 8.3, 1.1, Paint()..color = color);
        }
      case GameIcons.solved:
        canvas.drawCircle(const Offset(12, 12), 8.3, outline);
        stroke(
          Path()
            ..moveTo(8.2, 12.4)
            ..lineTo(10.9, 15.1)
            ..lineTo(16, 9.4),
        );
      case GameIcons.open:
        stroke(
          Path()
            ..moveTo(9.5, 6.5)
            ..lineTo(15, 12)
            ..lineTo(9.5, 17.5),
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(GameIconPainter old) => old.icon != icon || old.color != color || old.fill != fill;
}
