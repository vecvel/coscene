// Paints every puzzle type in its three states (being set up, failing,
// solved) and checks nothing throws. Set COSCENE_SHOTS to a folder to also
// save each frame as a PNG for a visual check:
//
//   COSCENE_SHOTS=/tmp/shots flutter test test/render_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:coscene_content/coscene_content.dart';
import 'package:coscene_core/coscene_core.dart';
import 'package:coscene_render/coscene_render.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const double _pixels = 600;

Future<void> _shoot(WidgetTester tester, String name, void Function(Canvas canvas) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, _pixels, _pixels), Paint()..color = Palette.cream);
  draw(canvas);
  final picture = recorder.endRecording();
  final dir = Platform.environment['COSCENE_SHOTS'];
  if (dir != null) {
    await tester.runAsync(() async {
      final image = await picture.toImage(_pixels.toInt(), _pixels.toInt());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }
  picture.dispose();
}

void _paintScene(Canvas canvas, SceneDelegate delegate, {Playback? playback, Map<String, dynamic>? ghost}) {
  final logical = delegate.logicalSize;
  final scale = _pixels / (logical.width > logical.height ? logical.width : logical.height);
  canvas.save();
  canvas.scale(scale);
  delegate.paint(
    canvas,
    PaintContext(
      playback: playback,
      time: playback?.timeline.duration ?? 0,
      ghost: ghost,
      clock: 0,
      reduceMotion: false,
    ),
  );
  canvas.restore();
}

void main() {
  final registry = LevelRegistry.bundled();
  final engine = Engine.standard;

  for (final id in [
    'p01-l06',
    'p02-l08',
    'p03-l08',
    'p04-l08',
    'p05-l08',
    'p06-l08',
    'p07-l08',
    'p08-l08',
    'p09-l02',
    'p09-l08',
    'p10-l01',
    'p10-l03',
    'p10-l04',
    'p10-l10',
  ]) {
    testWidgets('paints $id in every state', (tester) async {
      final level = registry.byId(id)!;
      final scene = engine.createScene(level);
      final delegate = delegateFor(scene);

      await _shoot(tester, '$id-1-setup', (c) => _paintScene(c, delegate));

      final failed = scene.simulate();
      expect(failed.outcome.success, isFalse);
      final ghost = scene.snapshot();
      await _shoot(
        tester,
        '$id-2-failed',
        (c) => _paintScene(c, delegate, playback: Playback(failed.outcome, failed.timeline)),
      );

      scene.restore(engine.solve(level)!.state);
      delegate.sync();
      await _shoot(tester, '$id-3-ghost', (c) => _paintScene(c, delegate, ghost: ghost));

      final solved = scene.simulate();
      expect(solved.outcome.success, isTrue);
      // Mid-way and at the end of the winning playback.
      for (final (label, fraction) in [('4-playing', 0.5), ('5-solved', 1.0)]) {
        await _shoot(tester, '$id-$label', (c) {
          final logical = delegate.logicalSize;
          c.save();
          c.scale(_pixels / (logical.width > logical.height ? logical.width : logical.height));
          delegate.paint(
            c,
            PaintContext(
              playback: Playback(solved.outcome, solved.timeline),
              time: solved.timeline.duration * fraction,
              ghost: null,
              clock: 0,
              reduceMotion: false,
            ),
          );
          c.restore();
        });
      }
    });
  }

  testWidgets('touches never throw and edits are reported', (tester) async {
    for (final level in registry.levels.where((l) => l.index == 5 || l.place >= 9)) {
      final scene = engine.createScene(level);
      final delegate = delegateFor(scene);
      var edits = 0;
      delegate.onChanged = () => edits++;
      delegate.onFeedback = (_) {};
      // Sweep a grid of taps and drags across the scene.
      for (var y = 5.0; y < 100; y += 9) {
        for (var x = 5.0; x < 100; x += 9) {
          final p = Offset(x, y);
          if (delegate.onDown(p)) {
            // Alternate between a short nudge and a long carry up the scene.
            final to = (x + y) % 2 < 1 ? p + const Offset(7, -11) : Offset(x + 3, 34);
            delegate.onMove(to);
            delegate.onUp(to);
          } else {
            delegate.onTap(p);
          }
          delegate.tick(1 / 60);
        }
      }
      expect(edits, greaterThan(0), reason: '${level.id} (${level.archetypeId}) ignored every touch');
      // Whatever the touches did, the scene must still be judgeable.
      scene.evaluate();
      scene.restore(scene.snapshot());
    }
  });

  testWidgets('every icon paints, plain, greyed and filled', (tester) async {
    await _shoot(tester, 'icons', (c) {
      for (var i = 0; i < GameIcons.values.length; i++) {
        final col = i % 5, row = i ~/ 5;
        for (final (dx, dy, size, color, inside) in [
          (0.0, 0.0, 72.0, Palette.ink, null),
          (0.0, 84.0, 24.0, Palette.ink, null),
          (34.0, 84.0, 24.0, Palette.stone, null),
          (68.0, 84.0, 24.0, Palette.ink, Palette.mustard),
        ]) {
          c.save();
          c.translate(24.0 + col * 112 + dx, 24.0 + row * 150 + dy);
          GameIconPainter(GameIcons.values[i], color, fill: inside).paint(c, Size.square(size));
          c.restore();
        }
      }
    });
  });

  testWidgets('logo paints at rest, mid-intro and with bleed', (tester) async {
    await _shoot(tester, 'logo-rest', (c) {
      c.clipRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, _pixels, _pixels), const Radius.circular(135)));
      Logo.paint(c, const Rect.fromLTWH(0, 0, _pixels, _pixels));
    });
    await _shoot(tester, 'logo-intro', (c) => Logo.paint(c, const Rect.fromLTWH(0, 0, _pixels, _pixels), time: 5.7));
    await _shoot(tester, 'logo-bleed', (c) => Logo.paint(c, const Rect.fromLTWH(150, 150, 300, 300), bleed: 60));
  });
}
