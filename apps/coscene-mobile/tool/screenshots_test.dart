// Renders the main screens to PNG files for a visual check. Run from
// apps/coscene-mobile:
//
//   COSCENE_SHOTS=/some/folder flutter test tool/screenshots_test.dart
//
// Latin text uses Roboto from the Flutter SDK. Other scripts need the
// phone's own fonts, so check those on a device.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:coscene/app.dart';
import 'package:coscene/services/save_store.dart';
import 'package:coscene_core/coscene_core.dart';
import 'package:coscene_render/coscene_render.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> loadFonts() async {
  // The test runner lives in <flutter>/bin/cache/artifacts/engine/<host>/.
  final cache = File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
  final fonts = '$cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold', 'Black']) {
    final file = File('$fonts/Roboto-$weight.ttf');
    if (file.existsSync()) roboto.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await roboto.load();
}

void main() {
  final out = Platform.environment['COSCENE_SHOTS'];

  Future<void> shoot(WidgetTester tester, String name) async {
    if (out == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$out/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('main screens', (tester) async {
    await tester.runAsync(loadFonts);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final save = jsonEncode({
      'v': 1,
      'language': 'en',
      'name': 'Asha',
      'levels': {
        for (var i = 1; i <= 8; i++) 'p01-l0$i': {'stars': i.isEven ? 3 : 2, 'attempts': 2, 'hints': 0},
        for (var i = 1; i <= 4; i++) 'p02-l0$i': {'stars': 3, 'attempts': 1, 'hints': 0},
      },
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('shot'),
        child: CosceneApp(store: MemorySaveStore(save)),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await shoot(tester, '1-home');

    await tester.tap(find.byWidgetPredicate((w) => w is GameIcon && w.icon == GameIcons.play));
    await tester.pumpAndSettle();
    await shoot(tester, '2-scene');

    // Solve it the way a player would, then press the action button.
    final view = tester.widget<SceneView>(find.byType(SceneView));
    final scene = view.delegate.scene;
    scene.restore(Engine.standard.solve(scene.level)!.state);
    view.delegate.sync();
    await tester.tap(find.text('Lift'));
    for (var i = 0; i < 45; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await shoot(tester, '3-reveal');
  });

  testWidgets('profile card', (tester) async {
    await tester.runAsync(loadFonts);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final save = jsonEncode({
      'v': 1,
      'language': 'en',
      'name': 'Asha',
      'levels': {
        for (var p = 1; p <= 4; p++)
          for (var i = 1; i <= 9; i++) 'p0$p-l0$i': {'stars': 3, 'attempts': 1, 'hints': 0},
      },
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('shot'),
        child: CosceneApp(store: MemorySaveStore(save)),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('cosIQ '));
    await tester.pumpAndSettle();
    await shoot(tester, '4-profile');
  });
}
