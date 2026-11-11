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

  group('balance', () {
    final level = spec('balance_levers', {
      'halfSpan': 4,
      'fixed': [
        {'weight': 3, 'slot': -2},
      ],
      'movable': [
        {'weight': 2, 'slot': 1},
      ],
    });

    test('heavier side wins until weight times distance matches', () {
      final scene = engine.createScene(level) as BalanceScene;
      expect(scene.evaluate().kind, 'tips_left');
      expect(scene.place(1, 4), isTrue);
      expect(scene.evaluate().kind, 'tips_right');
      expect(scene.place(1, 3), isTrue);
      expect(scene.evaluate().success, isTrue);
    });

    test('rejects occupied, blocked and middle slots', () {
      final scene = engine.createScene(level) as BalanceScene;
      expect(scene.place(1, -2), isFalse);
      expect(scene.place(1, 0), isFalse);
      expect(scene.place(1, 9), isFalse);
      expect(scene.place(0, 3), isFalse, reason: 'fixed loads do not move');
    });

    test('solver finds the single balancing slot', () {
      expect(engine.solve(level)!.state['slots'], [3]);
      expect(engine.inspect(level).ok, isTrue);
    });
  });

  group('ray', () {
    Map<String, dynamic> room(double mirrorDegrees) => {
      'size': 100,
      'emitter': {'x': 10, 'y': 50, 'degrees': 0},
      'mirrors': [
        {'x': 50, 'y': 50, 'length': 16, 'degrees': mirrorDegrees, 'stepDegrees': 45},
      ],
      'target': {'x': 50, 'y': 10, 'radius': 4},
    };

    test('beam leaves a mirror at the angle it arrived', () {
      final scene = engine.createScene(spec('ray_reflection', room(135))) as RayScene;
      final t = scene.trace();
      expect(t.hit, isTrue);
      expect(t.bounces, 1);
      expect(t.points[1].x, closeTo(50, 1e-6));
      expect(t.points[1].y, closeTo(50, 1e-6));
    });

    test('wrong angle misses and reports the gap', () {
      final scene = engine.createScene(spec('ray_reflection', room(45))) as RayScene;
      final o = scene.evaluate();
      expect(o.kind, 'missed');
      expect(o.magnitude, greaterThan(0));
    });

    test('solver turns the mirror to the hitting angle', () {
      final level = spec('ray_reflection', room(0));
      expect(engine.solve(level)!.state['steps'], [3]);
    });
  });

  group('shadow', () {
    final level = spec(
      'area_projection',
      {
        'lamp': {
          'x': {'min': 20, 'max': 60, 'step': 10, 'value': 20},
          'height': {'min': 60, 'max': 60, 'step': 1, 'value': 60},
        },
        'board': {
          'x': {'min': 40, 'max': 40, 'step': 1, 'value': 40},
          'width': 10,
          'height': 30,
        },
        'target': {'from': 40, 'to': 60},
      },
      {'edgeTolerance': 0.5},
    );

    test('shadow is the board scaled from the lamp', () {
      final scene = engine.createScene(level) as ShadowScene;
      // Lamp at 20, twice as high as the board: everything doubles its
      // distance from the lamp.
      expect(scene.shadow.from, closeTo(60, 1e-9));
      expect(scene.shadow.to, closeTo(80, 1e-9));
      expect(scene.evaluate().kind, 'off_right');
    });

    test('sliding the lamp over the board lines the shadow up', () {
      final scene = engine.createScene(level) as ShadowScene;
      scene.lampX.moveTo(40);
      expect(scene.evaluate().success, isTrue);
      expect(engine.inspect(level).ok, isTrue);
    });
  });

  group('flow', () {
    final level = spec('volume_flow', {
      'tanks': [
        {'width': 2, 'height': 10, 'target': 6},
        {'width': 1, 'height': 10, 'target': 8},
      ],
      'valves': [
        {'tank': 0, 'max': 4},
        {'tank': 1, 'max': 4},
      ],
      'duration': {'min': 4, 'max': 4, 'step': 1, 'value': 4},
    });

    test('level is flow times time over width', () {
      final scene = engine.createScene(level) as FlowScene;
      scene.setRate(0, 3);
      scene.setRate(1, 2);
      expect(scene.levels, [6, 8]);
      expect(scene.evaluate().success, isTrue);
    });

    test('overflow beats every other failure', () {
      final scene = engine.createScene(level) as FlowScene;
      scene.setRate(1, 4);
      expect(scene.evaluate().kind, 'overflow');
    });

    test('a weak pump shares its flow', () {
      final shared = spec('volume_flow', {...level.initialState, 'supply': 4});
      final scene = engine.createScene(shared) as FlowScene;
      scene.setRate(0, 4);
      scene.setRate(1, 4);
      expect(scene.pressure, 0.5);
      expect(scene.levels, [4, 8]);
    });
  });

  group('routing', () {
    final level = spec('network_routing', {
      'colors': ['red', 'blue'],
      'items': ['red', 'blue', 'red'],
      'nodes': [
        {'id': 'in', 'kind': 'source', 'x': 50, 'y': 5, 'next': 'j'},
        {'id': 'j', 'kind': 'filter', 'x': 50, 'y': 40, 'left': 'a', 'right': 'b', 'state': 1},
        {'id': 'a', 'kind': 'bin', 'x': 25, 'y': 90, 'accepts': 'red'},
        {'id': 'b', 'kind': 'bin', 'x': 75, 'y': 90, 'accepts': 'blue'},
      ],
    });

    test('filter sends its colour left and the rest right', () {
      final scene = engine.createScene(level) as RoutingScene;
      expect(scene.evaluate().magnitude, 3);
      scene.cycle('j');
      expect(scene.evaluate().success, isTrue);
    });

    test('flip junction alternates sides', () {
      final flip = spec('network_routing', {
        'colors': ['red', 'blue'],
        'items': ['red', 'blue', 'red', 'blue'],
        'nodes': [
          {'id': 'in', 'kind': 'source', 'x': 50, 'y': 5, 'next': 'j'},
          {'id': 'j', 'kind': 'flip', 'x': 50, 'y': 40, 'left': 'a', 'right': 'b', 'state': 1},
          {'id': 'a', 'kind': 'bin', 'x': 25, 'y': 90, 'accepts': 'red'},
          {'id': 'b', 'kind': 'bin', 'x': 75, 'y': 90, 'accepts': 'blue'},
        ],
      });
      final scene = engine.createScene(flip) as RoutingScene;
      expect(scene.evaluate().success, isFalse);
      scene.cycle('j');
      expect([for (final t in scene.run()) t.bin], ['a', 'b', 'a', 'b']);
      expect(scene.evaluate().success, isTrue);
    });

    test('looping belts are rejected', () {
      final loop = spec('network_routing', {
        'colors': ['red'],
        'items': ['red'],
        'nodes': [
          {'id': 'in', 'kind': 'source', 'x': 50, 'y': 5, 'next': 'j'},
          {'id': 'j', 'kind': 'switch', 'x': 50, 'y': 40, 'left': 'j', 'right': 'a'},
          {'id': 'a', 'kind': 'bin', 'x': 25, 'y': 90, 'accepts': 'red'},
        ],
      });
      expect(() => engine.createScene(loop), throwsA(isA<LevelFormatException>()));
    });
  });

  group('locks', () {
    final level = spec('permutation_locks', {
      'dials': [
        {'positions': 4, 'value': 3, 'target': 0},
        {'positions': 4, 'value': 2, 'target': 0},
      ],
      'links': [
        [1, 1],
        [0, 1],
      ],
    });

    test('turning one dial drags its linked dial', () {
      final scene = engine.createScene(level) as LockScene;
      scene.turn(0, 1);
      expect([for (final d in scene.dials) d.value], [0, 3]);
      scene.turn(1, 1);
      expect(scene.evaluate().success, isTrue);
    });

    test('solver returns the shortest list of turns', () {
      final solution = engine.solve(level)!;
      expect(solution.effort, 2);
      final scene = engine.createScene(level) as LockScene;
      for (final m in solution.moves) {
        scene.turn(m[0], m[1]);
      }
      expect(scene.evaluate().success, isTrue);
    });

    test('unreachable targets are reported unsolvable', () {
      final stuck = spec('permutation_locks', {
        'dials': [
          {'positions': 4, 'value': 1, 'target': 0},
        ],
        'links': [
          [2],
        ],
      });
      expect(engine.solve(stuck), isNull);
      expect(engine.inspect(stuck).ok, isFalse);
    });
  });

  group('gears', () {
    final level = spec('gear_ratio', {
      'stages': [
        {
          'driver': {'teeth': 24},
          'driven': {'slot': 0},
        },
      ],
      'tray': [8, 12, 48],
      'slots': [null],
      'inputTurns': 1,
      'target': {'turns': 3},
    });

    test('a small driven gear spins faster', () {
      final scene = engine.createScene(level) as GearScene;
      expect(scene.evaluate().kind, 'missing_gear');
      scene.assign(0, 2);
      expect(scene.evaluate().kind, 'too_slow');
      scene.assign(0, 0);
      expect(scene.speeds.last, -3);
      expect(scene.evaluate().success, isTrue);
    });

    test('a tray gear can only be on one peg', () {
      final two = spec('gear_ratio', {
        'stages': [
          {
            'driver': {'slot': 0},
            'driven': {'slot': 1},
          },
        ],
        'tray': [10, 20],
        'slots': [0, null],
        'target': {'turns': 2},
      });
      final scene = engine.createScene(two) as GearScene;
      scene.assign(1, 0);
      expect(scene.slots, [null, 0]);
    });
  });

  group('cargo', () {
    final level = spec(
      'cargo_packing',
      {
        'hold': {'cols': 4, 'rows': 2},
        'pieces': [
          {'w': 2, 'h': 2, 'heavy': true},
          {'w': 1, 'h': 2},
          {'w': 1, 'h': 2},
        ],
      },
      {'balanceTolerance': 0.5},
    );

    test('crates cannot overlap or leave the hold', () {
      final scene = engine.createScene(level) as CargoScene;
      expect(scene.place(0, 0, 0, rotated: false), isTrue);
      expect(scene.place(1, 1, 0, rotated: false), isFalse);
      expect(scene.place(1, 3, 1, rotated: false), isFalse);
      expect(scene.place(1, 2, 0, rotated: false), isTrue);
    });

    test('heavy crate off-centre makes the ship list', () {
      final scene = engine.createScene(level) as CargoScene;
      scene.place(0, 0, 0, rotated: false);
      scene.place(1, 2, 0, rotated: false);
      scene.place(2, 3, 0, rotated: false);
      expect(scene.evaluate().kind, 'lists_left');
    });

    test('solver centres the heavy crate', () {
      final solution = engine.solve(level)!;
      expect((solution.state['pieces'] as List).first, [1, 0, 0]);
      expect(engine.inspect(level).ok, isTrue);
    });
  });

  group('session', () {
    final level = spec('balance_levers', {
      'halfSpan': 4,
      'fixed': [
        {'weight': 3, 'slot': -2},
      ],
      'movable': [
        {'weight': 2, 'slot': 1},
      ],
    });

    test('nothing is judged until the player submits', () {
      final session = PlaySession(engine, level);
      final scene = session.scene as BalanceScene;
      scene.place(1, 3);
      expect(session.solved, isFalse);
      expect(session.attempts, 0);
      final result = session.submit();
      expect(result.outcome.success, isTrue);
      expect(session.solved, isTrue);
      expect(session.stars, 3);
    });

    test('failed tries leave a ghost and cost stars', () {
      final session = PlaySession(engine, level);
      final scene = session.scene as BalanceScene;
      session.submit();
      session.submit();
      expect(session.ghost, {
        'slots': [1],
      });
      session.revealHint();
      scene.place(1, 3);
      session.submit();
      expect(session.failedAttempts, 2);
      expect(session.stars, 2);
    });

    test('playback is identical every time', () {
      final a = PlaySession(engine, level).submit().timeline;
      final b = PlaySession(engine, level).submit().timeline;
      for (var t = 0.0; t < a.duration; t += 0.1) {
        expect(a.at('angle', t), b.at('angle', t));
      }
      expect(a.last('angle'), lessThan(0), reason: 'left side is heavier');
    });
  });

  test('seeded generator repeats exactly', () {
    final a = Rng(42), b = Rng(42);
    expect([for (var i = 0; i < 8; i++) a.nextU32()], [for (var i = 0; i < 8; i++) b.nextU32()]);
    expect(Rng(1).nextU32(), isNot(Rng(2).nextU32()));
  });
}
