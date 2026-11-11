import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'draw.dart';
import 'palette.dart';

/// The coscene mark, drawn on a 120-unit square. The eyes sit where the
/// one-third lines cross, and the chin is one full cosine wave whose midline
/// is the two-thirds line, so the icon is two thirds orange.
abstract final class Logo {
  /// Length of the full intro animation at normal speed, in seconds.
  static const double introSeconds = 7.6;

  static double _slosh(double t) {
    if (t >= 5.4) return 0;
    final a = 0.7 * math.exp(-0.6 * t) * math.cos(3.4 * t);
    return t > 4.9 ? a * (5.4 - t) / 0.5 : a;
  }

  static double _back(double x) => 1 + 2.70158 * math.pow(x - 1, 3) + 1.70158 * math.pow(x - 1, 2);

  /// Paints the mark so that its 120-unit square fills [box].
  ///
  /// [time] is seconds into the intro, or null for the resting pose.
  /// [bleed] extends the orange, the wave and the arms that many units past
  /// the square on every side, for icons that are masked by the system.
  /// With [background] off only the eyes and glasses are drawn, and the arms
  /// stop short inside the square. With [mono] set, the mark is drawn as a
  /// single-colour silhouette (wave, frames and pupils) for themed icons.
  static void paint(
    Canvas canvas,
    Rect box, {
    double? time,
    double bleed = 0,
    bool background = true,
    double blink = 0,
    Color? mono,
  }) {
    final t = time ?? 99;
    final phi = _slosh(t);
    final speed = (_slosh(t + 0.01) - _slosh(t - 0.01)) / 0.02;
    final shut = blink > 0.5 || (t > 6.6 && t < 6.75) || (t > 7 && t < 7.15);

    canvas.save();
    canvas.translate(box.left, box.top);
    canvas.scale(box.width / 120);

    if (background) {
      if (mono == null) {
        canvas.drawRect(Rect.fromLTRB(-bleed, -bleed, 120 + bleed, 120 + bleed), fill(Palette.orange));
      }
      final wave = Path();
      for (var x = -bleed; x <= 120 + bleed + 0.01; x += 2) {
        final y = 80 - 20 * math.cos(math.pi * x / 60 - phi);
        if (x == -bleed) {
          wave.moveTo(x, y);
        } else {
          wave.lineTo(x, y);
        }
      }
      // The white runs a little past the orange so no orange edge shows
      // where the mark sits on a white card.
      wave
        ..lineTo(120 + bleed + 2, 80)
        ..lineTo(120 + bleed + 2, 122 + bleed)
        ..lineTo(-bleed - 2, 122 + bleed)
        ..lineTo(-bleed - 2, 80)
        ..close();
      canvas.drawPath(wave, fill(mono ?? Palette.white));
    }

    // Eyes ride the wave; pupils glance the way it is moving.
    final ride = 60 * phi / math.pi;
    var look = Offset((speed * 2.8).clamp(-6.5, 6.5), 0);
    if (t > 5.2 && t < 6.3) {
      look = Offset(0, -5 * math.min(1, math.min((t - 5.2) / 0.2, (6.3 - t) / 0.2)));
    }
    for (final cx in const [40.0, 80.0]) {
      final c = Offset(cx + ride, 40);
      if (mono == null) {
        canvas.drawOval(Rect.fromCenter(center: c, width: 30, height: shut ? 1.6 : 30), fill(Palette.white));
      }
      if (!shut) canvas.drawCircle(c + look, 7.5, fill(mono ?? Palette.ink));
    }

    // Glasses lift off, then drop back on with a small bounce.
    var drop = 0.0, tilt = 0.0, visible = true;
    if (t < 0.4) {
      drop = -110 * math.pow(t / 0.4, 2).toDouble();
      tilt = 10 * (t / 0.4);
    } else if (t < 5.4) {
      visible = false;
    } else if (t < 6.1) {
      final e = _back((t - 5.4) / 0.7);
      drop = -110 * (1 - e);
      tilt = -14 * (1 - e);
    }
    if (visible) {
      canvas.save();
      canvas.translate(60, 40 + drop);
      canvas.rotate(tilt * math.pi / 180);
      canvas.translate(-60, -40);
      final frame = line(mono ?? Palette.ink, 5, cap: StrokeCap.butt);
      canvas.drawCircle(const Offset(40, 40), 17.5, frame);
      canvas.drawCircle(const Offset(80, 40), 17.5, frame);
      canvas.drawLine(const Offset(57.5, 40), const Offset(62.5, 40), frame);
      if (background) {
        final reach = 30 + bleed;
        canvas.drawLine(const Offset(27.63, 27.63), Offset(-reach, -reach), frame);
        canvas.drawLine(const Offset(92.37, 27.63), Offset(120 + reach, -reach), frame);
      } else {
        // On its own the mark has no edge to run into, so the arms end
        // early with rounded tips.
        final arm = line(Palette.ink, 5);
        canvas.drawLine(const Offset(27.63, 27.63), const Offset(8, 8), arm);
        canvas.drawLine(const Offset(92.37, 27.63), const Offset(112, 8), arm);
      }
      canvas.restore();
    }
    canvas.restore();
  }
}

class LogoPainter extends CustomPainter {
  LogoPainter({this.time, this.cornerRadius = 0.225, this.background = true, this.blink = 0, super.repaint});

  final double? time;

  /// Corner radius as a share of the width. 0 leaves the square uncut.
  final double cornerRadius;
  final bool background;
  final double blink;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    if (background) {
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(box, Radius.circular(size.width * cornerRadius)));
    }
    Logo.paint(canvas, box, time: time, background: background, blink: blink);
    if (background) canvas.restore();
  }

  @override
  bool shouldRepaint(LogoPainter old) =>
      old.time != time || old.blink != blink || old.cornerRadius != cornerRadius || old.background != background;
}

/// The mark as a widget. With [animate] it plays the intro once.
class LogoMark extends StatefulWidget {
  const LogoMark({
    super.key,
    this.size = 96,
    this.animate = false,
    this.speed = 2.4,
    this.onDone,
    this.cornerRadius = 0.225,
  });

  final double size;
  final bool animate;

  /// Playback rate of the intro. 2.4 makes it a little over three seconds.
  final double speed;
  final VoidCallback? onDone;
  final double cornerRadius;

  @override
  State<LogoMark> createState() => _LogoMarkState();
}

class _LogoMarkState extends State<LogoMark> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: Duration(milliseconds: (Logo.introSeconds / widget.speed * 1000).round()),
        )..addStatusListener((s) {
          if (s == AnimationStatus.completed) widget.onDone?.call();
        });
    if (widget.animate) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: LogoPainter(
          time: widget.animate ? _controller.value * Logo.introSeconds : null,
          cornerRadius: widget.cornerRadius,
        ),
      ),
    ),
  );
}
