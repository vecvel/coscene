import 'dart:convert';
import 'dart:ui' as ui;

import 'package:coscene/app.dart';
import 'package:coscene/game/game_state.dart';
import 'package:coscene/screens/profile_screen.dart';
import 'package:coscene/services/audio.dart';
import 'package:coscene/services/save_store.dart';
import 'package:coscene/ui/kit.dart';
import 'package:coscene_core/coscene_core.dart';
import 'package:coscene_i18n/coscene_i18n.dart';
import 'package:coscene_render/coscene_render.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Solves a level the way a player would: set it up, then submit.
PlaySession solve(GameState game, LevelSpec level, {int failsFirst = 0, int hints = 0}) {
  final session = PlaySession(game.registry.engine, level);
  for (var i = 0; i < failsFirst; i++) {
    session.submit();
  }
  for (var i = 0; i < hints; i++) {
    session.revealHint();
  }
  session.scene.restore(game.registry.engine.solve(level)!.state);
  expect(session.submit().outcome.success, isTrue);
  return session;
}

Finder icon(GameIcons which) => find.byWidgetPredicate((w) => w is GameIcon && w.icon == which);

void main() {
  group('progress', () {
    test('a new player starts in the device language with one scene open', () async {
      final game = await GameState.load(MemorySaveStore(), deviceLanguages: ['te-IN', 'en']);
      expect(game.language, 'te');
      expect(game.totalSolved, 0);
      expect(game.score, scoreFloor);
      expect(game.rank, 1);
      expect(game.nextUp!.id, 'p01-l01');
      expect(game.isLevelOpen(game.registry.byId('p01-l02')!), isFalse);
      expect(game.isPlaceOpen(2), isFalse);
    });

    test('solving opens the next scene and, after seven, the next place', () async {
      final game = await GameState.load(MemorySaveStore());
      final levels = game.registry.levelsOf(1);
      for (var i = 0; i < 7; i++) {
        expect(game.isLevelOpen(levels[i]), isTrue);
        game.recordSolve(solve(game, levels[i]));
        if (i < 6) expect(game.isPlaceOpen(2), isFalse);
      }
      expect(game.isPlaceOpen(2), isTrue);
      expect(game.solvedIn(1), 7);
      expect(game.starsIn(1), 21);
      expect(game.score, greaterThan(scoreFloor));
    });

    test('the first solve of an idea adds it to the notebook once', () async {
      final game = await GameState.load(MemorySaveStore());
      final levels = game.registry.levelsOf(1);
      expect(game.recordSolve(solve(game, levels[0])), isTrue);
      expect(game.recordSolve(solve(game, levels[1])), isFalse, reason: 'same idea as the first scene');
      expect(game.foundConcepts, {levels[0].conceptId});
      expect(game.allConcepts, hasLength(24));
    });

    test('a better replay raises the stars, a worse one never lowers them', () async {
      final game = await GameState.load(MemorySaveStore());
      final level = game.registry.byId('p01-l01')!;
      game.recordSolve(solve(game, level, failsFirst: 5, hints: 2));
      expect(game.starsOf(level.id), 1);
      game.recordSolve(solve(game, level));
      expect(game.starsOf(level.id), 3);
      game.recordSolve(solve(game, level, failsFirst: 5));
      expect(game.starsOf(level.id), 3);
    });

    test('everything survives a restart', () async {
      final store = MemorySaveStore();
      final game = await GameState.load(store);
      game.recordSolve(solve(game, game.registry.byId('p01-l01')!, failsFirst: 2));
      game.setLanguage('ko');
      game.update(() {
        game.name = 'Asha';
        game.sound = false;
        game.leftHanded = true;
      });
      await game.saved;
      expect(jsonDecode(store.value!)['v'], 1);

      final again = await GameState.load(store, deviceLanguages: ['en']);
      expect(again.starsOf('p01-l01'), 2);
      expect(again.language, 'ko');
      expect(again.name, 'Asha');
      expect(again.sound, isFalse);
      expect(again.leftHanded, isTrue);
      expect(again.score, game.score);
    });

    test('a damaged save starts fresh instead of crashing', () async {
      final game = await GameState.load(MemorySaveStore('{not json'));
      expect(game.totalSolved, 0);
    });

    test('reset clears progress but keeps the language', () async {
      final game = await GameState.load(MemorySaveStore());
      game.setLanguage('hi');
      game.recordSolve(solve(game, game.registry.byId('p01-l01')!));
      await game.resetProgress();
      expect(game.totalSolved, 0);
      expect(game.language, 'hi');
    });

    test('all hundred scenes solved with three stars is the top score', () async {
      final game = await GameState.load(MemorySaveStore());
      for (final level in game.registry.levels) {
        game.recordSolve(solve(game, level));
      }
      expect(game.totalSolved, 100);
      expect(game.totalStars, 300);
      expect(game.score, scoreCeiling);
      expect(game.rank, 6);
      expect(game.nextUp, isNull);
      expect(game.foundConcepts, hasLength(24));
    });

    test('every language has a title for every rank', () async {
      final game = await GameState.load(MemorySaveStore());
      for (final lang in supportedLanguages) {
        game.setLanguage(lang.code);
        for (var rank = 1; rank <= rankThresholds.length; rank++) {
          expect(game.t('rank.$rank'), isNot('rank.$rank'));
        }
      }
    });
  });

  group('sound', () {
    test('every sound is synthesised, audible and never clips', () {
      for (final sfx in Sfx.values) {
        final samples = synthesize(sfx);
        expect(samples.length, greaterThan(200), reason: sfx.name);
        final peak = samples.map((s) => s.abs()).reduce((a, b) => a > b ? a : b);
        expect(peak, greaterThan(3000), reason: '${sfx.name} is too quiet');
        expect(peak, lessThan(32767), reason: '${sfx.name} clips');
        expect(samples.first.abs(), lessThan(400), reason: '${sfx.name} starts with a click');
        expect(samples.last.abs(), lessThan(400), reason: '${sfx.name} ends with a click');
        expect(synthesize(sfx), samples, reason: '${sfx.name} is not repeatable');
      }
    });
  });

  group('screens', () {
    Future<void> launch(WidgetTester tester, {String language = 'en'}) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(CosceneApp(store: MemorySaveStore(jsonEncode({'v': 1, 'language': language}))));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('launches to the home screen', (tester) async {
      await launch(tester);
      expect(find.text('coscene'), findsOneWidget);
      expect(find.text('Dockyard'), findsOneWidget);
      expect(find.text('Daily scene'), findsOneWidget);
      expect(find.textContaining('Play'), findsOneWidget);
    });

    testWidgets('a wrong setup plays out and says what went wrong', (tester) async {
      await launch(tester);
      await tester.tap(find.textContaining('Play'));
      await tester.pumpAndSettle();
      expect(find.text('Hang the loose crate so the arm stays level.'), findsOneWidget);
      expect(find.byType(SceneView), findsOneWidget);

      await tester.tap(find.text('Lift'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.textContaining('A crate is still on the ground.'), findsOneWidget);
      expect(find.textContaining('Adjust it and try again.'), findsOneWidget);
    });

    testWidgets('hints appear one at a time', (tester) async {
      await launch(tester);
      await tester.tap(find.textContaining('Play'));
      await tester.pumpAndSettle();
      await tester.tap(icon(GameIcons.hint));
      await tester.pumpAndSettle();
      expect(find.text('A crate pulls harder the farther out it hangs.'), findsNothing);
      await tester.tap(find.text('Show a hint'));
      await tester.pumpAndSettle();
      expect(find.text('A crate pulls harder the farther out it hangs.'), findsOneWidget);
      expect(find.text('Show another hint'), findsOneWidget);
    });

    for (final lang in supportedLanguages) {
      testWidgets('home, a scene and the profile fit the screen in ${lang.englishName}', (tester) async {
        // Any text that overflows its space fails the test.
        await launch(tester, language: lang.code);
        final game = GameScope.of(tester.element(find.byType(ListView).first));
        expect(game.language, lang.code);
        await tester.tap(find.text('cosIQ '));
        await tester.pumpAndSettle();
        expect(find.byType(CustomPaint), findsWidgets);
        await tester.tap(icon(GameIcons.back));
        await tester.pumpAndSettle();
        await tester.tap(icon(GameIcons.play));
        await tester.pumpAndSettle();
        expect(find.byType(SceneView), findsOneWidget);
      });
    }
  });

  testWidgets('the share card draws for a long name in every language', (tester) async {
    for (final lang in supportedLanguages) {
      final game = await tester.runAsync(() => GameState.load(MemorySaveStore()));
      game!.setLanguage(lang.code);
      game.name = 'A very long player name indeed';
      final recorder = ui.PictureRecorder();
      ShareCardPainter(CardData.of(game)).paint(Canvas(recorder), ShareCardPainter.cardSize);
      recorder.endRecording().dispose();
    }
  });
}
