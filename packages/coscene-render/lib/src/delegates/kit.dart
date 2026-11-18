import 'dart:math' as math;
import 'dart:ui';

import '../draw.dart';
import '../palette.dart';

/// A tappable rectangle in scene units, with what it does.
class Hit {
  const Hit(this.rect, this.action);
  final Rect rect;
  final void Function() action;
}

/// The logic scenes share one look: values sit in joined white strips, like
/// an array in a textbook, with hairlines between cells and room around the
/// text. Sizes are in scene units; the board is 100 wide.
const double margin = 4;
const double radius = 2.4;
const Color hairline = Palette.sand;
const Color peach = Color(0xFFFBE3D6);
const Color wrongTint = Color(0xFFF6D9CF);

/// A flat rounded tile.
void tile(Canvas canvas, Rect r, Color color, {double radius = radius, Color? border}) {
  final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
  canvas.drawRRect(rr, fill(color));
  if (border != null) canvas.drawRRect(rr, line(border, 0.35));
}

/// Text sized to fit [width], never bigger than [size].
void fitLabel(
  Canvas canvas,
  String text,
  Offset center,
  double width, {
  double size = 4.4,
  Color color = Palette.ink,
  FontWeight weight = FontWeight.w600,
  bool mono = false,
  double anchorX = 0.5,
}) {
  final perChar = mono ? 0.62 : 0.56;
  final fitted = (width / (text.length * perChar + 0.4)).clamp(2.2, size);
  drawLabel(canvas, text, center, size: fitted, color: color, weight: weight, mono: mono, anchorX: anchorX);
}

/// A small quiet caption, left-aligned at [at].
void caption(Canvas canvas, String text, Offset at, {double width = 60}) =>
    fitLabel(canvas, text, at, width, size: 3, color: Palette.inkSoft, weight: FontWeight.w500, anchorX: 0);

/// A white panel cut into [cols] × [rows] cells with hairlines between them.
/// [fillOf] colours single cells; the panel's corners stay round.
List<Rect> cellGrid(Canvas canvas, Rect r, int cols, {int rows = 1, Color? Function(int i)? fillOf}) {
  final w = r.width / cols, h = r.height / rows;
  final cells = [
    for (var i = 0; i < cols * rows; i++) Rect.fromLTWH(r.left + (i % cols) * w, r.top + (i ~/ cols) * h, w, h),
  ];
  final rr = RRect.fromRectAndRadius(r, const Radius.circular(radius));
  canvas.drawRRect(rr, fill(Palette.white));
  if (fillOf != null) {
    canvas.save();
    canvas.clipRRect(rr);
    for (var i = 0; i < cells.length; i++) {
      final c = fillOf(i);
      if (c != null) canvas.drawRect(cells[i], fill(c));
    }
    canvas.restore();
  }
  final hair = line(hairline, 0.3, cap: StrokeCap.butt);
  for (var x = 1; x < cols; x++) {
    canvas.drawLine(Offset(r.left + x * w, r.top), Offset(r.left + x * w, r.bottom), hair);
  }
  for (var y = 1; y < rows; y++) {
    canvas.drawLine(Offset(r.left, r.top + y * h), Offset(r.right, r.top + y * h), hair);
  }
  return cells;
}

/// A value in a cell, about 40% of its height, with an optional index under it.
void cellText(Canvas canvas, String text, Rect cell, {Color color = Palette.ink, String? index, Color? indexColor}) {
  final size = math.min(cell.height * (index == null ? 0.42 : 0.36), 4.6);
  final y = index == null ? cell.center.dy : cell.top + cell.height * 0.4;
  fitLabel(canvas, text, Offset(cell.center.dx, y), cell.width - 2.2, size: size, color: color);
  if (index != null) {
    drawLabel(
      canvas,
      index,
      Offset(cell.center.dx, cell.top + cell.height * 0.78),
      size: math.min(cell.height * 0.22, 2.8),
      color: indexColor ?? Palette.stone,
      weight: FontWeight.w500,
      mono: true,
    );
  }
}

/// Width of each cell in a strip of [n] cells across [available].
double cellWidth(int n, {double available = 100 - 2 * margin, double max = 11}) => math.min(max, available / n);

/// A button drawn in the scene: white tile, centred caption.
void button(Canvas canvas, Rect r, String caption, {bool enabled = true, bool selected = false}) {
  tile(canvas, r, selected ? Palette.ink : (enabled ? Palette.white : Palette.sand));
  fitLabel(
    canvas,
    caption,
    r.center,
    r.width - 4,
    size: math.min(4.2, r.height * 0.38),
    color: selected ? Palette.cream : (enabled ? Palette.ink : Palette.stone),
    weight: FontWeight.w500,
  );
}

/// A segmented control: a sand track with the chosen option as a dark pill.
/// Returns one rect per option for hit testing.
List<Rect> segmented(Canvas canvas, Rect r, List<String> options, int? chosen, {Color chosenColor = Palette.ink}) {
  tile(canvas, r, Palette.sand);
  final w = r.width / options.length;
  final out = <Rect>[];
  for (var i = 0; i < options.length; i++) {
    final slot = Rect.fromLTWH(r.left + i * w, r.top, w, r.height);
    out.add(slot);
    final on = chosen == i;
    if (on) tile(canvas, slot.deflate(0.7), chosenColor, radius: radius - 0.6);
    fitLabel(
      canvas,
      options[i],
      slot.center,
      w - 2.4,
      size: math.min(3.8, r.height * 0.42),
      color: on ? Palette.cream : Palette.ink,
      weight: FontWeight.w500,
    );
  }
  return out;
}

/// Picks the first hit containing [p].
bool tapHits(List<Hit> hits, Offset p) {
  for (final h in hits) {
    if (h.rect.inflate(0.6).contains(p)) {
      h.action();
      return true;
    }
  }
  return false;
}

/// How far a failed result shakes, in scene units.
double shake(double t) => t * 3;
