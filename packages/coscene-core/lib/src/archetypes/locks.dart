import '../level_spec.dart';
import '../scene.dart';

class LockDial {
  LockDial(this.positions, this.value, this.target) : initial = value;
  final int positions;
  final int target;
  final int initial;
  int value;
}

/// Dials joined by hidden linkages: turning one drags some of the others
/// along. The lock opens when every dial points at its mark.
class LockScene extends Scene {
  LockScene(super.level) {
    final s = JsonReader(level.initialState, level.id, 'initialState.');
    for (final d in s.objects('dials')) {
      dials.add(LockDial(d.integer('positions'), d.integer('value'), d.integer('target')));
    }
    final rows = s.list('links');
    if (dials.isEmpty || dials.length > 5 || rows.length != dials.length) {
      throw LevelFormatException('needs 1 to 5 dials and one link row per dial', levelId: level.id);
    }
    for (final row in rows) {
      if (row is! List || row.length != dials.length || row.any((e) => e is! int)) {
        throw LevelFormatException('each link row needs one integer per dial', levelId: level.id);
      }
      links.add(row.cast<int>());
    }
    for (final d in dials) {
      if (d.positions < 2 ||
          d.positions > 12 ||
          d.value < 0 ||
          d.value >= d.positions ||
          d.target < 0 ||
          d.target >= d.positions) {
        throw LevelFormatException('dial values must fit their positions', levelId: level.id);
      }
    }
    for (var i = 0; i < dials.length; i++) {
      if (links[i][i] == 0) throw LevelFormatException('a dial must turn itself', levelId: level.id);
    }
  }

  final List<LockDial> dials = [];

  /// `links[i][j]` is how many clicks dial j moves when dial i turns one click.
  final List<List<int>> links = [];

  /// Turns a dial by [delta] clicks, dragging its linked dials with it.
  void turn(int dial, int delta) {
    for (var j = 0; j < dials.length; j++) {
      final d = dials[j];
      d.value = (d.value + links[dial][j] * delta) % d.positions;
      if (d.value < 0) d.value += d.positions;
    }
  }

  int get misaligned => dials.where((d) => d.value != d.target).length;

  @override
  void reset() {
    for (final d in dials) {
      d.value = d.initial;
    }
  }

  @override
  Map<String, dynamic> snapshot() => {
    'values': [for (final d in dials) d.value],
  };

  @override
  void restore(Map<String, dynamic> snapshot) {
    final values = (snapshot['values'] as List).cast<int>();
    if (values.length != dials.length) throw ArgumentError('snapshot does not fit this level');
    for (var i = 0; i < dials.length; i++) {
      if (values[i] < 0 || values[i] >= dials[i].positions) throw ArgumentError('snapshot value out of range');
      dials[i].value = values[i];
    }
  }

  @override
  Outcome evaluate() {
    final off = misaligned;
    return off == 0 ? const Outcome.solved() : Outcome.failed('jammed', magnitude: off.toDouble());
  }

  @override
  SimResult simulate() {
    final outcome = evaluate();
    final b = TimelineBuilder(80);
    if (outcome.success) {
      b.spring('open', target: 1, omega: 11, damping: 0.45, delay: 8);
      b.fill('rattle', (_) => 0);
    } else {
      b.fill('open', (_) => 0);
      b.spring('rattle', target: 0, velocity: 9, omega: 38, damping: 0.12);
    }
    return SimResult(outcome, b.build());
  }
}

class LockArchetype extends Archetype {
  const LockArchetype();

  @override
  String get id => 'permutation_locks';

  @override
  LockScene create(LevelSpec level) => LockScene(level);

  /// Shortest list of turns from the starting position to the open one.
  List<List<int>>? shortestPath(LockScene scene) {
    final n = scene.dials.length;
    final radix = [for (final d in scene.dials) d.positions];
    int encode(List<int> v) {
      var code = 0;
      for (var i = 0; i < n; i++) {
        code = code * radix[i] + v[i];
      }
      return code;
    }

    List<int> decode(int code) {
      final v = List<int>.filled(n, 0);
      for (var i = n - 1; i >= 0; i--) {
        v[i] = code % radix[i];
        code ~/= radix[i];
      }
      return v;
    }

    final start = encode([for (final d in scene.dials) d.initial]);
    final goal = encode([for (final d in scene.dials) d.target]);
    final parent = <int, int>{start: -1};
    final via = <int, List<int>>{};
    final queue = <int>[start];
    for (var head = 0; head < queue.length; head++) {
      final code = queue[head];
      if (code == goal) {
        final moves = <List<int>>[];
        for (var c = code; parent[c] != -1; c = parent[c]!) {
          moves.add(via[c]!);
        }
        return moves.reversed.toList();
      }
      final v = decode(code);
      for (var i = 0; i < n; i++) {
        for (final delta in const [1, -1]) {
          final next = List<int>.generate(n, (j) {
            final x = (v[j] + scene.links[i][j] * delta) % radix[j];
            return x < 0 ? x + radix[j] : x;
          });
          final nc = encode(next);
          if (!parent.containsKey(nc)) {
            parent[nc] = code;
            via[nc] = [i, delta];
            queue.add(nc);
          }
        }
      }
    }
    return null;
  }

  @override
  Solution? solve(LevelSpec level) {
    final scene = create(level);
    final moves = shortestPath(scene);
    if (moves == null) return null;
    return Solution(
      {
        'values': [for (final d in scene.dials) d.target],
      },
      effort: moves.length,
      moves: moves,
    );
  }

  @override
  double? winFraction(LevelSpec level) {
    final scene = create(level);
    var states = 1;
    for (final d in scene.dials) {
      states *= d.positions;
    }
    return 1 / states;
  }
}
