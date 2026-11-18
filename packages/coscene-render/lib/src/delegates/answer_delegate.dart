import 'dart:math' as math;
import 'dart:ui';

import 'package:coscene_core/coscene_core.dart';

import '../draw.dart';
import '../palette.dart';
import '../scene_delegate.dart';
import 'kit.dart';

/// One piece of the layout, top to bottom.
class _Block {
  const _Block(this.height, this.paint, {this.gapAfter = 4});
  final double height;
  final double gapAfter;
  final void Function(Canvas canvas, double y, PaintContext ctx) paint;
}

/// Shows what to work out, the fields for the answer and, when a number is
/// needed, a keypad. Arrays are joined strips, expressions plain text, and a
/// field whose label matches an expression shares its row.
class AnswerDelegate extends SceneDelegate<AnswerScene> {
  AnswerDelegate(super.scene) {
    _active = scene.fields.indexWhere((f) => f.mode == 'number');
    _blocks = _build();
  }

  static const double _w = 100;
  static const double _right = _w - margin;
  static const double _lineH = 11;
  static const double _keyH = 8.4;
  static const double _keyGap = 1.6;

  int _active = -1;
  final List<Hit> _hits = [];
  late final List<_Block> _blocks;

  @override
  Size get logicalSize {
    var h = 2.0;
    for (final b in _blocks) {
      h += b.height + b.gapAfter;
    }
    return Size(_w, h);
  }

  void _type(int digit) {
    if (_active < 0) return;
    final f = scene.fields[_active];
    final next = (f.value ?? 0) * 10 + digit;
    if ((f.value == null || f.value == 0) && digit == 0) {
      f.value = 0;
    } else if (next > f.max) {
      feedback(SceneFeedback.reject);
      return;
    } else {
      f.value = f.value == null ? digit : next;
    }
    feedback(SceneFeedback.tick);
    changed();
  }

  void _erase() {
    if (_active < 0) return;
    final f = scene.fields[_active];
    final v = f.value;
    if (v == null) return;
    f.value = v < 10 ? null : v ~/ 10;
    feedback(SceneFeedback.tick);
    changed();
  }

  @override
  void onTap(Offset p) => tapHits(_hits, p);

  @override
  void paint(Canvas canvas, PaintContext ctx) {
    _hits.clear();
    var y = 2.0;
    for (final b in _blocks) {
      b.paint(canvas, y, ctx);
      y += b.height + b.gapAfter;
    }
  }

  // ------------------------------------------------------------ layout

  List<_Block> _build() {
    final rows = scene.board;
    final fields = scene.fields;
    // An expression row and a field with the same label are drawn as one line.
    final pairOf = <int, int>{};
    for (var i = 0; i < fields.length; i++) {
      final label = fields[i].label;
      if (label.isEmpty) continue;
      final r = rows.indexWhere((row) => row.kind == 'expr' && row.label == label);
      if (r >= 0) pairOf[i] = r;
    }
    final paired = pairOf.values.toSet();
    final blocks = <_Block>[];

    for (var r = 0; r < rows.length; r++) {
      if (paired.contains(r)) continue;
      final row = rows[r];
      if (row.kind == 'expr') {
        blocks.add(_exprBlock(row));
        continue;
      }
      // Unlabelled rows of the same length in a run form one grid.
      var end = r + 1;
      if (row.label.isEmpty && !row.index) {
        while (end < rows.length &&
            rows[end].kind == row.kind &&
            rows[end].label.isEmpty &&
            !rows[end].index &&
            rows[end].cells.length == row.cells.length) {
          end++;
        }
      }
      blocks.add(_cellsBlock(rows.sublist(r, end)));
      r = end - 1;
    }
    if (blocks.isNotEmpty) {
      final last = blocks.removeLast();
      blocks.add(_Block(last.height, last.paint, gapAfter: 7));
    }

    final lined = fields.any((f) => f.label.isNotEmpty);
    if (lined) {
      blocks.add(_linesBlock([for (var i = 0; i < fields.length; i++) i], pairOf));
    } else {
      for (var i = 0; i < fields.length; i++) {
        blocks.add(fields[i].mode == 'number' ? _bigNumberBlock(i) : _choiceBlock(i));
      }
    }
    if (fields.any((f) => f.mode == 'number')) {
      final last = blocks.removeLast();
      blocks
        ..add(_Block(last.height, last.paint, gapAfter: 6))
        ..add(_Block(4 * _keyH + 3 * _keyGap, (c, y, _) => _paintKeypad(c, y), gapAfter: 1));
    }
    return blocks;
  }

  _Block _exprBlock(BoardRow row) {
    final text = row.label.isEmpty ? row.cells.first : '${row.label}:  ${row.cells.first}';
    return _Block(
      7,
      (c, y, _) => fitLabel(c, text, Offset(_w / 2, y + 3.5), _w - 2 * margin, size: 4.6, mono: true),
      gapAfter: 3,
    );
  }

  _Block _cellsBlock(List<BoardRow> group) {
    final first = group.first;
    final n = first.cells.length;
    final grid = group.length > 1;
    final cw = cellWidth(n, max: grid ? 9 : 11);
    final ch = grid ? cw : (first.index ? 12.5 : 10.5);
    final label = first.label.isNotEmpty ? 5.0 : 0.0;
    final total = n * cw;
    final x0 = (_w - total) / 2;
    return _Block(label + ch * group.length, (c, y, _) {
      if (label > 0) caption(c, first.label, Offset(x0 + 0.6, y + 1.8), width: total);
      final rect = Rect.fromLTWH(x0, y + label, total, ch * group.length);
      Color? colorOf(int i) {
        final row = group[i ~/ n];
        final v = row.cells[i % n];
        if (v == '■') return Palette.ink;
        if (row.kind == 'bits' && v == '1') return Palette.ink;
        if (row.mark.contains(i % n)) return Palette.mustard;
        return null;
      }

      final cells = cellGrid(c, rect, n, rows: group.length, fillOf: colorOf);
      for (var i = 0; i < cells.length; i++) {
        final row = group[i ~/ n];
        final v = row.cells[i % n];
        if (v == '■' || v == '·') continue;
        final dark = row.kind == 'bits' && v == '1';
        cellText(
          c,
          v,
          cells[i],
          color: dark ? Palette.cream : Palette.ink,
          index: row.index ? '${i % n}' : null,
          indexColor: dark ? Palette.stone : null,
        );
      }
    });
  }

  ({double reveal, bool ok, double dx}) _judge(PaintContext ctx, int i) {
    final reveal = ctx.track('reveal$i');
    final ok = ctx.track('ok$i') > 0.5;
    final dx = ctx.finished || ok ? 0.0 : shake(ctx.track('shake'));
    return (reveal: reveal, ok: ok, dx: dx);
  }

  void _focus(int i) {
    _active = i;
    feedback(SceneFeedback.tick);
    changed();
  }

  _Block _bigNumberBlock(int i) {
    return _Block(12, (c, y, ctx) {
      final f = scene.fields[i];
      final j = _judge(ctx, i);
      final judged = j.reveal > 0.5;
      final r = Rect.fromLTWH(22 + j.dx, y, _w - 44, 12);
      if (judged) tile(c, r, j.ok ? Palette.tealTint : wrongTint);
      final v = f.value;
      fitLabel(
        c,
        v == null ? '?' : '$v',
        Offset(r.center.dx, r.center.dy - 0.4),
        r.width - 4,
        size: 6.2,
        color: v == null ? Palette.stone : (judged ? (j.ok ? Palette.tealDeep : Palette.coralDeep) : Palette.ink),
      );
      if (!judged) {
        final active = _active == i;
        c.drawLine(
          Offset(r.left + 4, r.bottom - 0.6),
          Offset(r.right - 4, r.bottom - 0.6),
          line(active ? Palette.ink : Palette.stone, active ? 0.7 : 0.4),
        );
      }
      _hits.add(Hit(r, () => _focus(i)));
    });
  }

  _Block _choiceBlock(int i) {
    return _Block(9, (c, y, ctx) {
      final f = scene.fields[i];
      final j = _judge(ctx, i);
      final options = f.mode == 'bool' ? const ['false', 'true'] : f.options;
      final judged = j.reveal > 0.5;
      final color = judged ? (j.ok ? Palette.teal : Palette.coralDeep) : Palette.ink;
      final slots = segmented(
        c,
        Rect.fromLTWH(margin + 10 + j.dx, y, _w - 2 * margin - 20, 9),
        options,
        f.value,
        chosenColor: color,
      );
      for (var o = 0; o < slots.length; o++) {
        _hits.add(Hit(slots[o], () => _choose(f, o)));
      }
    });
  }

  void _choose(AnswerField f, int o) {
    f.value = o;
    feedback(SceneFeedback.tick);
    changed();
  }

  /// Labelled fields as lines in one white panel: the question on the left,
  /// the answer on the right.
  _Block _linesBlock(List<int> idx, Map<int, int> pairOf) {
    final height = idx.length * _lineH;
    return _Block(height, (c, y, ctx) {
      final panel = Rect.fromLTWH(margin, y, _w - 2 * margin, height);
      cellGrid(c, panel, 1, rows: idx.length);
      for (var k = 0; k < idx.length; k++) {
        final i = idx[k];
        final f = scene.fields[i];
        final top = y + k * _lineH;
        final mid = top + _lineH / 2;
        final j = _judge(ctx, i);
        final judged = j.reveal > 0.5;
        final controlW = f.mode == 'number'
            ? 26.0
            : (f.mode == 'bool' ? 34.0 : math.min(52.0, 14.0 * f.options.length));
        final controlR = Rect.fromLTWH(_right - 2 - controlW + j.dx, top + 1.8, controlW, _lineH - 3.6);
        final textW = controlR.left - margin - 6;
        final pair = pairOf[i];
        if (pair != null) {
          drawLabel(
            c,
            f.label,
            Offset(margin + 3, mid),
            size: 2.9,
            color: Palette.stone,
            weight: FontWeight.w500,
            anchorX: 0,
          );
          fitLabel(
            c,
            scene.board[pair].cells.first,
            Offset(margin + 8, mid),
            textW - 5,
            size: 4.2,
            mono: true,
            anchorX: 0,
          );
        } else {
          final mono = !f.label.startsWith('@');
          fitLabel(
            c,
            labelText(f.label),
            Offset(margin + 3, mid),
            textW,
            size: 4,
            mono: mono,
            color: mono ? Palette.ink : Palette.inkSoft,
            weight: mono ? FontWeight.w600 : FontWeight.w500,
            anchorX: 0,
          );
        }
        if (f.mode == 'number') {
          if (judged) tile(c, controlR, j.ok ? Palette.tealTint : wrongTint);
          final v = f.value;
          fitLabel(
            c,
            v == null ? '?' : '$v',
            controlR.center,
            controlR.width - 3,
            size: 4.6,
            color: v == null ? Palette.stone : (judged ? (j.ok ? Palette.tealDeep : Palette.coralDeep) : Palette.ink),
          );
          if (!judged) {
            final active = _active == i;
            c.drawLine(
              Offset(controlR.left + 2, controlR.bottom - 0.3),
              Offset(controlR.right - 2, controlR.bottom - 0.3),
              line(active ? Palette.ink : Palette.stone, active ? 0.6 : 0.35),
            );
          }
          _hits.add(Hit(Rect.fromLTWH(margin, top, _w - 2 * margin, _lineH), () => _focus(i)));
        } else {
          final options = f.mode == 'bool' ? const ['false', 'true'] : f.options;
          final color = judged ? (j.ok ? Palette.teal : Palette.coralDeep) : Palette.ink;
          final slots = segmented(c, controlR, options, f.value, chosenColor: color);
          for (var o = 0; o < slots.length; o++) {
            _hits.add(Hit(slots[o], () => _choose(f, o)));
          }
        }
      }
    });
  }

  void _paintKeypad(Canvas canvas, double y) {
    const cols = 3;
    final w = (_w - 2 * margin - 2 * _keyGap) / cols;
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];
    for (var k = 0; k < keys.length; k++) {
      final key = keys[k];
      if (key.isEmpty) continue;
      final r = Rect.fromLTWH(margin + (k % cols) * (w + _keyGap), y + (k ~/ cols) * (_keyH + _keyGap), w, _keyH);
      tile(canvas, r, Palette.white);
      drawLabel(canvas, key, r.center, size: key == '⌫' ? 3.6 : 4.2, weight: FontWeight.w500);
      _hits.add(Hit(r, key == '⌫' ? _erase : () => _type(int.parse(key))));
    }
  }
}
