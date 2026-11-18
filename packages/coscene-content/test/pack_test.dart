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
  'answer': ['empty', 'wrong', 'some_wrong'],
  'probe': ['out_of_checks'],
  'pick': [
    'empty',
    'wrong_count',
    'too_much',
    'too_little',
    'wrong_xor',
    'not_together',
    'not_best',
    'overlap',
    'over_cap',
  ],
  'ops': ['wrong_order', 'unfinished', 'unsorted', 'too_many_moves', 'too_early'],
  'route': ['unfinished', 'longer'],
};

void main() {
  final engine = Engine.standard;
  final registry = LevelRegistry.bundled();
  final levels = registry.levels;

  group('bundled pack', () {
    test('has 300 levels: thirty topics of ten, ten topics per tier', () {
      expect(levels, hasLength(300));
      expect(registry.places, hasLength(30));
      for (var tier = 0; tier < 3; tier++) {
        expect(registry.places.where((p) => p.tier == tier), hasLength(10));
      }
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

    test('searches can be won by halving within the budget', () {
      for (final level in levels.where((l) => l.archetypeId == 'probe')) {
        final scene = engine.createScene(level) as ProbeScene;
        for (final move in engine.solve(level)!.moves) {
          scene.check(move[0]);
        }
        expect(scene.evaluate().success, isTrue, reason: level.id);
        expect(scene.checks.length, scene.budget, reason: '${level.id}: the budget has no slack');
      }
    });

    test('easy, medium and hard sit in their own difficulty bands', () {
      for (final level in levels) {
        final tier = tierOfPlace(level.place);
        expect(level.difficulty, inInclusiveRange(tier * 3 + 1, tier * 3 + 3), reason: level.id);
      }
    });

    test('difficulty climbs and no two levels are the same', () {
      for (final place in registry.places) {
        final d = registry.levelsOf(place.number).map((l) => l.difficulty).toList();
        expect(d, [...d]..sort(), reason: '${place.id} gets easier somewhere');
      }
      expect(
        levels.map((l) => jsonEncode([l.initialState, l.validationRules, l.textParams])).toSet(),
        hasLength(levels.length),
      );
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
        topic: registry.place(first.place)!.id,
        difficulty: first.difficulty,
        seed: Rng.hash('coscene-base-${first.id}-v2'),
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
        for (final key in keys) {
          expect(dictionaries['en']![key], isNotNull, reason: '${level.id}: "$key" missing in English');
        }
        for (final entry in dictionaries.entries) {
          final dictionary = LocaleManager.instance.dictionary(entry.key);
          for (final key in keys) {
            // Until a language is translated it falls back to English.
            expect(dictionary.t(key), isNot(key), reason: '${level.id}: "$key" in ${entry.key}');
          }
          // Numbers in the text come from the level, with nothing left over.
          final objective = LocaleManager.instance.dictionary(entry.key).t(level.objectiveKey, level.textParams);
          expect(objective, isNot(contains('{')), reason: '${level.id} in ${entry.key}: $objective');
        }
      }
    });

    test('every place has a name and tagline in every language', () {
      for (final place in registry.places) {
        for (final code in dictionaries.keys) {
          final dictionary = LocaleManager.instance.dictionary(code);
          expect(
            dictionary.t('place.${place.id}.name'),
            isNot('place.${place.id}.name'),
            reason: '${place.id} in $code',
          );
          expect(dictionary.t('place.${place.id}.tagline'), isNot('place.${place.id}.tagline'));
        }
      }
    });

    test('failure kinds listed here are the ones the engine produces', () {
      // Random setups on every level must only fail in ways we have text for.
      for (final level in levels) {
        final short = archetypeShortNames[level.archetypeId]!;
        final outcome = engine.createScene(level).evaluate();
        if (outcome.isProgress) continue;
        expect(failKinds[short], contains(outcome.kind), reason: level.id);
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
