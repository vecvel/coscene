// The validation suite for level content: every bundled level loads, is
// solvable, and has its text in all eight languages.
import 'dart:convert';
import 'dart:io';

import 'package:coscene_content/coscene_content.dart';
import 'package:coscene_content/src/pack_io.dart';
import 'package:coscene_core/coscene_core.dart';
import 'package:coscene_i18n/coscene_i18n.dart';
import 'package:test/test.dart';

const failKinds = {
  'balance': ['unplaced', 'tips_left', 'tips_right'],
  'ray': ['missed', 'too_direct'],
  'shadow': ['too_wide', 'too_narrow', 'off_left', 'off_right'],
  'flow': ['overflow', 'too_low', 'too_high'],
  'routing': ['misplaced'],
  'locks': ['jammed'],
  'gears': ['missing_gear', 'too_fast', 'too_slow'],
  'cargo': ['left_behind', 'lists_left', 'lists_right'],
};

void main() {
  final engine = Engine.standard;
  final registry = LevelRegistry.bundled();
  final levels = registry.levels;

  group('bundled pack', () {
    test('has 100 levels: ten places of ten', () {
      expect(levels, hasLength(100));
      expect(registry.places, hasLength(10));
      for (final place in registry.places) {
        final inPlace = registry.levelsOf(place.number);
        expect(inPlace.map((l) => l.index), List.generate(10, (i) => i + 1), reason: place.id);
        expect(inPlace.map((l) => l.id), [for (var i = 1; i <= 10; i++) levelId(place.number, i)]);
      }
    });

    test('uses every archetype the engine knows', () {
      expect(levels.map((l) => l.archetypeId).toSet(), engine.archetypeIds.toSet());
    });

    test('every level loads, starts unsolved, and can be solved', () {
      for (final level in levels) {
        final report = engine.inspect(level);
        expect(report.issues, isEmpty, reason: level.id);
        // Play it through the same loop the app uses.
        final session = PlaySession(engine, level);
        expect(session.submit().outcome.success, isFalse, reason: '${level.id} starts solved');
        session.scene.restore(report.solution!.state);
        final result = session.submit();
        expect(result.outcome.success, isTrue, reason: '${level.id} solution rejected');
        expect(result.timeline.frames, greaterThan(0));
        expect(session.stars, inInclusiveRange(1, 3));
      }
    });

    test('lock levels can be opened by legal turns alone', () {
      for (final level in levels.where((l) => l.archetypeId == 'permutation_locks')) {
        final scene = engine.createScene(level) as LockScene;
        for (final move in engine.solve(level)!.moves) {
          scene.turn(move[0], move[1]);
        }
        expect(scene.evaluate().success, isTrue, reason: level.id);
      }
    });

    test('difficulty climbs and no two levels are the same', () {
      for (final place in registry.places) {
        final d = registry.levelsOf(place.number).map((l) => l.difficulty).toList();
        expect(d, [...d]..sort(), reason: '${place.id} gets easier somewhere');
      }
      expect(levels.map((l) => jsonEncode(l.initialState)).toSet(), hasLength(levels.length));
    });

    test('survives a JSON round trip unchanged', () {
      for (final level in levels) {
        final copy = LevelSpec.fromJson(jsonDecode(jsonEncode(level.toJson())) as Map<String, dynamic>);
        expect(jsonEncode(copy.toJson()), jsonEncode(level.toJson()));
      }
    });

    test('embedded copy matches the JSON files', () {
      final onDisk = readPackDirectory('levels/base');
      expect(
        jsonEncode(onDisk.toJson()),
        jsonEncode(loadBundledPack().toJson()),
        reason: 'run: dart run tool/generate_levels.dart --embed',
      );
    });

    test('generation is repeatable', () {
      final first = levels.first;
      final again = generateLevel(
        id: first.id,
        place: first.place,
        index: first.index,
        archetypeId: first.archetypeId,
        difficulty: first.difficulty,
        seed: Rng.hash('coscene-base-${first.id}-v1'),
      );
      expect(jsonEncode(again.toJson()), jsonEncode(first.toJson()));
    });
  });

  group('text', () {
    final dictionaries = {for (final lang in supportedLanguages) lang.code: LocaleManager.instance.entries(lang.code)};

    test('all eight languages are present', () {
      expect(dictionaries.keys, ['en', 'hi', 'bn', 'as', 'ta', 'te', 'id', 'ko']);
    });

    test('objectives, hints and reveals resolve in every language', () {
      for (final level in levels) {
        final short = archetypeShortNames[level.archetypeId]!;
        final keys = [
          level.objectiveKey,
          level.revealKey,
          ...level.hints,
          'concept.${level.conceptId}.name',
          'concept.${level.conceptId}.idea',
          'concept.${level.conceptId}.seen',
          'action.$short',
          'tip.$short',
          'ok.$short',
          for (final kind in failKinds[short]!) 'fail.$short.$kind',
        ];
        expect(level.hints.length, greaterThanOrEqualTo(3), reason: level.id);
        for (final entry in dictionaries.entries) {
          for (final key in keys) {
            expect(entry.value[key], isNotNull, reason: '${level.id}: "$key" missing in ${entry.key}');
            expect(entry.value[key]!.trim(), isNotEmpty);
          }
          // Numbers in the text come from the level, with nothing left over.
          final objective = LocaleManager.instance.dictionary(entry.key).t(level.objectiveKey, level.textParams);
          expect(objective, isNot(contains('{')), reason: '${level.id} in ${entry.key}: $objective');
        }
      }
    });

    test('every place has a name and tagline in every language', () {
      for (final place in registry.places) {
        for (final entry in dictionaries.entries) {
          expect(entry.value['place.${place.id}.name'], isNotNull, reason: '${place.id} in ${entry.key}');
          expect(entry.value['place.${place.id}.tagline'], isNotNull, reason: '${place.id} in ${entry.key}');
        }
      }
    });

    test('failure kinds listed here are the ones the engine produces', () {
      // Random setups on every level must only fail in ways we have text for.
      for (final level in levels) {
        final short = archetypeShortNames[level.archetypeId]!;
        final kind = engine.createScene(level).evaluate().kind;
        expect(failKinds[short], contains(kind), reason: level.id);
      }
    });
  });

  group('daily scene', () {
    test('a month of days all produce a solvable scene', () {
      final seen = <String>{};
      for (var day = 0; day < 31; day++) {
        final date = DateTime(2027, 1, 1).add(Duration(days: day));
        final level = dailyLevel(date);
        expect(engine.inspect(level).issues, isEmpty, reason: level.id);
        expect(level.place, dailyPlace);
        seen.add(level.archetypeId);
        expect(jsonEncode(dailyLevel(date).toJson()), jsonEncode(level.toJson()), reason: 'not repeatable');
      }
      expect(seen, hasLength(engine.archetypeIds.length));
    });
  });

  test('level files are valid JSON with the schema fields', () {
    for (final file in Directory('levels/base').listSync().whereType<File>()) {
      if (!file.path.contains('place-')) continue;
      final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final l in doc['levels'] as List) {
        for (final field in ['id', 'archetypeId', 'initialState', 'validationRules', 'hints', 'i18nKey']) {
          expect((l as Map).containsKey(field), isTrue, reason: '${file.path}: missing $field');
        }
      }
    }
  });
}
