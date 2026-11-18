import '../level_spec.dart';
import '../rng.dart';
import '../scene.dart';

/// Reach a goal through a sequence of moves.
///
/// * `stack`: items arrive in order; push the next one or pop the top to the
///   output, until the output reads `target`. An optional `cap` limits the
///   stack height.
/// * `swap`: sort the row within `budget` swaps; with `adjacent` only
///   neighbours can swap.
/// * `order`: put every task in an order where each one comes after the tasks
///   it depends on (`deps` holds pairs `[before, after]`).
class OpsScene extends Scene {
  OpsScene(super.level) {
    final s = JsonReader(level.initialState, level.id, 'initialState.');
    mode = s.string('mode');
    items = s.integers('items');
    target = s.integers('target', optional: true);
    cap = s.integer('cap', orElse: 0);
    adjacent = s.boolean('adjacent', orElse: false);
    budget = s.integer('budget', orElse: 0);
    labels = s.strings('labels', optional: true);
    for (final d in s.list('deps', optional: true)) {
      if (d is! List || d.length != 2 || d.any((e) => e is! int || e < 0 || e >= items.length)) {
        throw LevelFormatException('each dependency is a pair of task indexes', levelId: level.id);
      }
      deps.add((d[0] as int, d[1] as int));
    }
    if (items.length < 2 || items.length > 10) {
      throw LevelFormatException('needs 2 to 10 items', levelId: level.id);
    }
    switch (mode) {
      case 'stack':
        if (target.length != items.length || ({...target}.length != items.length) || !target.every(items.contains)) {
          throw LevelFormatException('the target must use every item once', levelId: level.id);
        }
      case 'swap':
        if (budget < 1) throw LevelFormatException('swaps need a budget', levelId: level.id);
      case 'order':
        if (labels.length != items.length) throw LevelFormatException('every task needs a label', levelId: level.id);
      default:
        throw LevelFormatException('ops mode "$mode" is not known', levelId: level.id);
    }
    reset();
  }

  late final String mode;
  late final List<int> items;
  late final List<int> target;
  late final int cap;
  late final bool adjacent;
  late final int budget;
  late final List<String> labels;
  final List<(int, int)> deps = [];

  /// Moves made so far. Stack: 0 push, 1 pop. Swap: i * 16 + j. Order: task.
  final List<int> moves = [];

  // Stack state.
  int next = 0;
  final List<int> stack = [];
  final List<int> output = [];

  // Swap state.
  late List<int> row;

  @override
  void reset() {
    moves.clear();
    next = 0;
    stack.clear();
    output.clear();
    row = [...items];
  }

  bool get canPush => mode == 'stack' && next < items.length && (cap == 0 || stack.length < cap);
  bool get canPop => mode == 'stack' && stack.isNotEmpty;

  /// Applies one move. Returns false, changing nothing, when it is not allowed.
  bool apply(int move) {
    switch (mode) {
      case 'stack':
        if (move == 0) {
          if (!canPush) return false;
          stack.add(items[next++]);
        } else {
          if (!canPop) return false;
          output.add(stack.removeLast());
        }
      case 'swap':
        final i = move ~/ 16, j = move % 16;
        if (i == j || i < 0 || j < 0 || i >= row.length || j >= row.length) return false;
        if (adjacent && (i - j).abs() != 1) return false;
        final t = row[i];
        row[i] = row[j];
        row[j] = t;
      default:
        if (move < 0 || move >= items.length || moves.contains(move)) return false;
    }
    moves.add(move);
    return true;
  }

  /// Takes back the last move.
  void undo() {
    if (moves.isEmpty) return;
    final kept = moves.sublist(0, moves.length - 1);
    reset();
    kept.forEach(apply);
  }

  bool get sorted {
    for (var i = 1; i < row.length; i++) {
      if (row[i] < row[i - 1]) return false;
    }
    return true;
  }

  @override
  Map<String, dynamic> snapshot() => {
    'moves': [...moves],
  };

  @override
  void restore(Map<String, dynamic> snapshot) {
    final list = (snapshot['moves'] as List).cast<int>();
    reset();
    for (final m in list) {
      if (!apply(m)) throw ArgumentError('snapshot holds a move that is not allowed');
    }
  }

  @override
  Outcome evaluate() {
    switch (mode) {
      case 'stack':
        for (var i = 0; i < output.length; i++) {
          if (output[i] != target[i]) return Outcome.failed('wrong_order', detail: {'at': i});
        }
        if (output.length < target.length) return const Outcome.failed('unfinished');
        return const Outcome.solved();
      case 'swap':
        if (!sorted) return const Outcome.failed('unsorted');
        if (moves.length > budget) {
          return Outcome.failed('too_many_moves', magnitude: (moves.length - budget).toDouble());
        }
        return const Outcome.solved();
      default:
        if (moves.length < items.length) return const Outcome.failed('unfinished');
        final at = {for (var i = 0; i < moves.length; i++) moves[i]: i};
        for (final (a, b) in deps) {
          if (at[a]! > at[b]!) return Outcome.failed('too_early', detail: {'task': b});
        }
        return const Outcome.solved();
    }
  }

  @override
  SimResult simulate() {
    final outcome = evaluate();
    final b = TimelineBuilder(46);
    b.ramp('sweep', 0, 30);
    if (outcome.success) {
      b.spring('pop', target: 1, omega: 12, damping: 0.4, delay: 26);
    } else {
      b.spring('shake', target: 0, velocity: 6, omega: 32, damping: 0.15, delay: 26);
    }
    return SimResult(outcome, b.build());
  }
}

class OpsArchetype extends Archetype {
  const OpsArchetype();

  @override
  String get id => 'ops';

  @override
  OpsScene create(LevelSpec level) => OpsScene(level);

  /// Fewest swaps that sort [row]: inversions for neighbour swaps, otherwise
  /// the length minus the number of cycles.
  static int fewestSwaps(List<int> row, {required bool adjacent}) {
    if (adjacent) {
      var inv = 0;
      for (var i = 0; i < row.length; i++) {
        for (var j = i + 1; j < row.length; j++) {
          if (row[i] > row[j]) inv++;
        }
      }
      return inv;
    }
    final order = List<int>.generate(row.length, (i) => i)..sort((a, b) => row[a].compareTo(row[b]));
    final seen = List<bool>.filled(row.length, false);
    var swaps = 0;
    for (var i = 0; i < row.length; i++) {
      var len = 0;
      for (var j = i; !seen[j]; j = order[j]) {
        seen[j] = true;
        len++;
      }
      if (len > 1) swaps += len - 1;
    }
    return swaps;
  }

  @override
  Solution? solve(LevelSpec level) {
    final scene = create(level);
    final moves = <int>[];
    switch (scene.mode) {
      case 'stack':
        for (final t in scene.target) {
          while (scene.stack.isEmpty || scene.stack.last != t) {
            if (!scene.apply(0)) return null;
            moves.add(0);
          }
          scene.apply(1);
          moves.add(1);
        }
      case 'swap':
        final row = scene.row;
        if (scene.adjacent) {
          for (var pass = 0; pass < row.length; pass++) {
            for (var i = 0; i + 1 < row.length; i++) {
              if (row[i] > row[i + 1]) {
                final m = i * 16 + i + 1;
                scene.apply(m);
                moves.add(m);
              }
            }
          }
        } else {
          for (var i = 0; i < row.length; i++) {
            var min = i;
            for (var j = i + 1; j < row.length; j++) {
              if (row[j] < row[min]) min = j;
            }
            if (min != i) {
              final m = i * 16 + min;
              scene.apply(m);
              moves.add(m);
            }
          }
        }
      default:
        final done = <int>{};
        while (done.length < scene.items.length) {
          final ready = [
            for (var t = 0; t < scene.items.length; t++)
              if (!done.contains(t) && scene.deps.every((d) => d.$2 != t || done.contains(d.$1))) t,
          ];
          if (ready.isEmpty) return null;
          scene.apply(ready.first);
          moves.add(ready.first);
          done.add(ready.first);
        }
    }
    if (!scene.evaluate().success) return null;
    return Solution(
      {'moves': moves},
      effort: moves.length,
      moves: [
        for (final m in moves) [m],
      ],
    );
  }

  /// Chance that random allowed moves win. Counted exactly for task orders,
  /// estimated by repeated random play for the others.
  @override
  double? winFraction(LevelSpec level) {
    final scene = create(level);
    if (scene.mode == 'order') {
      final n = scene.items.length;
      final need = List<int>.filled(n, 0);
      for (final (a, b) in scene.deps) {
        need[b] |= 1 << a;
      }
      final ways = List<double>.filled(1 << n, 0)..[0] = 1;
      for (var mask = 0; mask < (1 << n); mask++) {
        if (ways[mask] == 0) continue;
        for (var t = 0; t < n; t++) {
          if (mask & (1 << t) == 0 && need[t] & mask == need[t]) ways[mask | (1 << t)] += ways[mask];
        }
      }
      var orders = 1.0;
      for (var i = 2; i <= n; i++) {
        orders *= i;
      }
      return ways[(1 << n) - 1] / orders;
    }
    if (scene.mode == 'swap') return null;
    final rng = Rng(Rng.hash(level.id));
    const runs = 400;
    var wins = 0;
    for (var t = 0; t < runs; t++) {
      scene.reset();
      while (scene.canPush || scene.canPop) {
        final push = scene.canPush && (!scene.canPop || rng.chance(0.5));
        scene.apply(push ? 0 : 1);
      }
      if (scene.evaluate().success) wins++;
    }
    scene.reset();
    return wins / runs;
  }
}
