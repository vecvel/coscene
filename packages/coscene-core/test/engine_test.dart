import 'package:coscene_core/coscene_core.dart';
import 'package:test/test.dart';

LevelSpec spec(String archetype, Map<String, dynamic> state, [Map<String, dynamic> rules = const {}]) => LevelSpec(
  id: 'test',
  archetypeId: archetype,
  place: 1,
  index: 1,
  difficulty: 1,
  initialState: state,
  validationRules: rules,
  hints: const ['hint.a'],
  i18nKey: 'scene.test',
  conceptId: 'test',
);

void main() {
  final engine = Engine.standard;

  group('answer', () {
    final level = spec(
      'answer',
      {
        'board': [
          {'kind': 'expr', 'text': '13 mod 5'},
        ],
        'fields': [
          {'mode': 'number', 'max': 9},
          {'mode': 'bool'},
        ],
      },
      {
        'answers': [3, 1],
      },
    );

    test('every field must hold the right value', () {
      final scene = engine.createScene(level) as AnswerScene;
      expect(scene.evaluate().kind, 'empty');
      scene.fields[0].value = 3;
      scene.fields[1].value = 0;
      expect(scene.evaluate().kind, 'some_wrong');
      scene.fields[1].value = 1;
      expect(scene.evaluate().success, isTrue);
    });

    test('random answers win as often as the fields allow', () {
      expect(engine.archetype('answer').winFraction(level), closeTo(1 / 20, 1e-9));
    });

    test('answers outside their field are rejected as bad data', () {
      final bad = spec('answer', level.initialState, {
        'answers': [12, 1],
      });
      expect(engine.inspect(bad).ok, isFalse);
    });
  });

  group('probe', () {
    final level = spec('probe', {'mode': 'compare', 'lo': 1, 'hi': 100, 'budget': 6});

    test('halving pins down 100 numbers in 6 checks', () {
      expect(ProbeArchetype.checksNeeded(100, 'compare'), 6);
      final report = engine.inspect(level);
      expect(report.ok, isTrue, reason: report.issues.join(', '));
      expect(report.solution!.moves, hasLength(6));
    });

    test('the hidden number dodges a lucky edge guess', () {
      final scene = engine.createScene(level) as ProbeScene;
      expect(scene.check(1), 'higher');
      expect(scene.candidates, 99);
    });

    test('each check is progress until the budget runs out', () {
      final scene = engine.createScene(level) as ProbeScene;
      for (var i = 0; i < 5; i++) {
        scene.pick = scene.lo;
        expect(scene.simulate().outcome.isProgress, isTrue);
      }
      scene.pick = scene.lo;
      expect(scene.simulate().outcome.kind, 'out_of_checks');
      scene.pick = 50;
      scene.simulate();
      expect(scene.checks, hasLength(1), reason: 'a spent search starts over');
    });

    test('bisect keeps the checked version when it is bad', () {
      final scene = engine.createScene(spec('probe', {'mode': 'bisect', 'lo': 1, 'hi': 8, 'budget': 3})) as ProbeScene;
      scene.check(4);
      expect([scene.lo, scene.hi], anyOf(equals([1, 4]), equals([5, 8])));
      expect(ProbeArchetype.checksNeeded(8, 'bisect'), 3);
    });
  });

  group('pick', () {
    test('a sum needs the right total and count', () {
      final scene =
          engine.createScene(
                spec(
                  'pick',
                  {
                    'tiles': [
                      for (final v in [2, 5, 8, 11]) {'v': v},
                    ],
                  },
                  {'rule': 'sum', 'target': 13, 'count': 2},
                ),
              )
              as PickScene;
      scene.picked.addAll([1, 2]);
      expect(scene.evaluate().success, isTrue);
      scene.picked
        ..clear()
        ..addAll([0, 3]);
      expect(scene.evaluate().success, isTrue, reason: '2 + 11 also works');
      scene.picked.remove(0);
      expect(scene.evaluate().kind, 'wrong_count');
    });

    test('an interval choice must be the largest that fits', () {
      final level = spec(
        'pick',
        {
          'layout': 'bars',
          'tiles': [
            {'v': 1, 's': 0, 'e': 4},
            {'v': 1, 's': 1, 'e': 2},
            {'v': 1, 's': 2, 'e': 3},
            {'v': 1, 's': 3, 'e': 5},
          ],
        },
        {'rule': 'intervals', 'best': 3},
      );
      final scene = engine.createScene(level) as PickScene;
      expect(PickArchetype.bestPossible(scene), 3);
      scene.picked.addAll([0]);
      expect(scene.evaluate().kind, 'not_best');
      scene.picked
        ..clear()
        ..addAll([1, 2, 3]);
      expect(scene.evaluate().success, isTrue);
      scene.picked.add(0);
      expect(scene.evaluate().kind, 'overlap');
    });

    test('a knapsack over the limit fails before value counts', () {
      final level = spec(
        'pick',
        {
          'layout': 'items',
          'tiles': [
            {'v': 10, 'w': 5},
            {'v': 6, 'w': 3},
            {'v': 6, 'w': 3},
          ],
        },
        {'rule': 'knapsack', 'cap': 6, 'best': 12},
      );
      final scene = engine.createScene(level) as PickScene;
      scene.picked.addAll([0, 1]);
      expect(scene.evaluate().kind, 'over_cap');
      scene.picked
        ..clear()
        ..addAll([1, 2]);
      expect(scene.evaluate().success, isTrue, reason: 'two light items beat the most valuable one');
    });
  });

  group('ops', () {
    test('a stack can produce 3 1 2 only with the right pushes and pops', () {
      final level = spec('ops', {
        'mode': 'stack',
        'items': [1, 2, 3],
        'target': [2, 3, 1],
      });
      final scene = engine.createScene(level) as OpsScene;
      expect(scene.apply(1), isFalse, reason: 'nothing to pop yet');
      for (final m in [0, 0, 1, 0, 1, 1]) {
        expect(scene.apply(m), isTrue);
      }
      expect(scene.evaluate().success, isTrue);
      expect(engine.inspect(level).ok, isTrue);
    });

    test('sorting by neighbour swaps needs one swap per inversion', () {
      expect(OpsArchetype.fewestSwaps([3, 1, 2], adjacent: true), 2);
      expect(OpsArchetype.fewestSwaps([3, 1, 2], adjacent: false), 2);
      expect(OpsArchetype.fewestSwaps([2, 1, 4, 3], adjacent: false), 2);
      final level = spec('ops', {
        'mode': 'swap',
        'items': [3, 1, 2],
        'adjacent': true,
        'budget': 2,
      });
      final scene = engine.createScene(level) as OpsScene;
      expect(scene.apply(0 * 16 + 2), isFalse, reason: 'not neighbours');
      scene
        ..apply(0 * 16 + 1)
        ..apply(1 * 16 + 2);
      expect(scene.evaluate().success, isTrue);
    });

    test('a task order must respect every dependency', () {
      final level = spec('ops', {
        'mode': 'order',
        'items': [0, 1, 2],
        'labels': ['A', 'B', 'C'],
        'deps': [
          [0, 1],
          [1, 2],
        ],
      });
      final scene = engine.createScene(level) as OpsScene;
      for (final t in [1, 0, 2]) {
        scene.apply(t);
      }
      expect(scene.evaluate().kind, 'too_early');
      expect(engine.archetype('ops').winFraction(level), closeTo(1 / 6, 1e-9));
    });
  });

  group('route', () {
    final level = spec(
      'route',
      {
        'cols': 3,
        'rows': 3,
        'cells': [1, 9, 1, 1, 9, 1, 1, 1, 1],
        'start': [0, 0],
        'goal': [2, 0],
      },
      {'best': 6},
    );

    test('the cheapest path goes around the expensive cells', () {
      final scene = engine.createScene(level) as RouteScene;
      expect(RouteArchetype.cheapest(scene), [0, 3, 6, 7, 8, 5, 2]);
      for (final c in [1, 2]) {
        scene.stepTo(c);
      }
      expect(scene.evaluate().kind, 'longer');
    });

    test('stepping back onto the path trims it', () {
      final scene = engine.createScene(level) as RouteScene;
      scene
        ..stepTo(3)
        ..stepTo(6)
        ..stepTo(3);
      expect(scene.path, [0, 3]);
      expect(scene.stepTo(8), isFalse, reason: 'not a neighbour');
    });
  });

  group('session', () {
    final level = spec(
      'answer',
      {
        'board': [
          {'kind': 'expr', 'text': '2 + 2'},
        ],
        'fields': [
          {'mode': 'number', 'max': 9},
        ],
      },
      {
        'answers': [4],
      },
    );

    test('nothing is judged until the player submits', () {
      final session = PlaySession(engine, level);
      (session.scene as AnswerScene).fields.first.value = 4;
      expect(session.solved, isFalse);
      expect(session.attempts, 0);
      expect(session.submit().outcome.success, isTrue);
      expect(session.stars, 3);
    });

    test('failed tries leave a ghost and cost stars', () {
      final session = PlaySession(engine, level);
      final scene = session.scene as AnswerScene;
      scene.fields.first.value = 5;
      session.submit();
      session.submit();
      expect(session.ghost, {
        'values': [5],
      });
      session.revealHint();
      scene.fields.first.value = 4;
      session.submit();
      expect(session.failedAttempts, 2);
      expect(session.stars, 2);
    });

    test('search checks are not failed tries', () {
      final session = PlaySession(engine, spec('probe', {'mode': 'compare', 'lo': 1, 'hi': 16, 'budget': 4}));
      final scene = session.scene as ProbeScene;
      for (var i = 0; i < 4; i++) {
        scene.pick = (scene.lo + scene.hi) ~/ 2;
        session.submit();
      }
      expect(session.solved, isTrue);
      expect(session.failedAttempts, 0);
      expect(session.attempts, 1, reason: 'only the final check counts as a try');
    });

    test('playback is identical every time', () {
      final a = PlaySession(engine, level).submit().timeline;
      final b = PlaySession(engine, level).submit().timeline;
      for (var t = 0.0; t < a.duration; t += 0.1) {
        expect(a.at('shake', t), b.at('shake', t));
      }
    });
  });

  test('seeded generator repeats exactly', () {
    final a = Rng(42), b = Rng(42);
    expect([for (var i = 0; i < 8; i++) a.nextU32()], [for (var i = 0; i < 8; i++) b.nextU32()]);
    expect(Rng(1).nextU32(), isNot(Rng(2).nextU32()));
  });
}
