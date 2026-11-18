import '../level_spec.dart';
import '../rng.dart';
import '../scene.dart';

/// Pin down a hidden value with a limited number of checks.
///
/// The hidden value is not fixed in advance: every answer keeps as many
/// candidates alive as it honestly can, so lucky guesses never help and only
/// halving the range fits the budget. In `compare` mode a check of g says
/// "lower" or "higher"; in `bisect` mode it says whether g is already "bad"
/// (the first bad version is at or before g).
class ProbeScene extends Scene {
  ProbeScene(super.level) {
    final s = JsonReader(level.initialState, level.id, 'initialState.');
    mode = s.string('mode', orElse: 'compare');
    lo0 = s.integer('lo');
    hi0 = s.integer('hi');
    budget = s.integer('budget');
    if (!const {'compare', 'bisect'}.contains(mode) || hi0 - lo0 < 2 || hi0 - lo0 > 4095 || budget < 1) {
      throw LevelFormatException('needs a known mode, 3 to 4096 candidates and a budget', levelId: level.id);
    }
    pick = (lo0 + hi0) ~/ 2;
    reset();
  }

  late final String mode;
  late final int lo0;
  late final int hi0;
  late final int budget;

  /// The value the player is about to check.
  late int pick;

  /// Checks made so far, oldest first, with the answer each one got.
  final List<({int value, String answer})> checks = [];
  late int lo;
  late int hi;

  /// True after the budget ran out without a find; the next check starts over.
  bool spent = false;

  int get candidates => hi - lo + 1;
  int get checksLeft => budget - checks.length;

  @override
  void reset() {
    checks.clear();
    lo = lo0;
    hi = hi0;
    spent = false;
  }

  /// Applies one check of [g] and returns the answer it gets.
  String check(int g) {
    final v = g.clamp(lo0, hi0);
    String answer;
    if (mode == 'compare') {
      if (v < lo) {
        answer = 'higher';
      } else if (v > hi) {
        answer = 'lower';
      } else {
        // Keep the bigger side alive. Ties go up.
        final below = v - lo, above = hi - v;
        if (below == 0 && above == 0) {
          answer = 'found';
        } else if (above >= below) {
          answer = 'higher';
          lo = v + 1;
        } else {
          answer = 'lower';
          hi = v - 1;
        }
      }
    } else {
      // Bad at g means the first bad one is at or before g.
      if (v < lo) {
        answer = 'good';
      } else if (v >= hi) {
        answer = 'bad';
        hi = hi < v ? hi : v;
      } else {
        final ifBad = v - lo + 1, ifGood = hi - v;
        if (ifGood >= ifBad) {
          answer = 'good';
          lo = v + 1;
        } else {
          answer = 'bad';
          hi = v;
        }
      }
    }
    checks.add((value: v, answer: answer));
    return answer;
  }

  @override
  Map<String, dynamic> snapshot() => {
    'checks': [for (final c in checks) c.value],
    'pick': pick,
  };

  @override
  void restore(Map<String, dynamic> snapshot) {
    final list = (snapshot['checks'] as List).cast<int>();
    reset();
    for (final g in list) {
      check(g);
    }
    pick = (snapshot['pick'] as int?) ?? pick;
  }

  @override
  Outcome evaluate() {
    if (candidates == 1 && checks.length <= budget) return Outcome.solved({'value': lo});
    if (checks.length >= budget) return Outcome.failed('out_of_checks', magnitude: candidates.toDouble());
    return Outcome.progress({'say': checks.isEmpty ? 'start' : checks.last.answer, 'left': candidates});
  }

  @override
  SimResult simulate() {
    if (spent) reset();
    // Once only one number is left there is nothing more to check.
    if (candidates > 1) check(pick);
    final outcome = evaluate();
    if (!outcome.success && !outcome.isProgress) spent = true;
    final b = TimelineBuilder(outcome.isProgress ? 24 : 44);
    b.ramp('narrow', 0, 18);
    if (outcome.success) b.spring('pop', target: 1, omega: 12, damping: 0.4, delay: 14);
    return SimResult(outcome, b.build());
  }
}

class ProbeArchetype extends Archetype {
  const ProbeArchetype();

  @override
  String get id => 'probe';

  @override
  ProbeScene create(LevelSpec level) => ProbeScene(level);

  /// Fewest checks that always pin the value down, from [n] candidates.
  static int checksNeeded(int n, String mode) {
    var count = 0;
    while (n > 1) {
      // compare: a middle check leaves the bigger half of the rest.
      // bisect: a middle check leaves the bigger of the two halves.
      n = mode == 'compare' ? n ~/ 2 : (n + 1) ~/ 2;
      count++;
    }
    return count;
  }

  @override
  Solution? solve(LevelSpec level) {
    final scene = create(level);
    final moves = <List<int>>[];
    while (scene.candidates > 1 && scene.checks.length < scene.budget) {
      final g = scene.mode == 'compare' ? (scene.lo + scene.hi) ~/ 2 : (scene.lo + scene.hi - 1) ~/ 2;
      scene.check(g);
      moves.add([g]);
    }
    if (scene.candidates != 1) return null;
    return Solution(scene.snapshot(), effort: moves.length, moves: moves);
  }

  /// Share of runs that win when every check is a random candidate.
  @override
  double? winFraction(LevelSpec level) {
    final scene = create(level);
    final rng = Rng(Rng.hash(level.id));
    const runs = 400;
    var wins = 0;
    for (var t = 0; t < runs; t++) {
      scene.reset();
      while (scene.candidates > 1 && scene.checks.length < scene.budget) {
        scene.check(scene.lo + rng.nextInt(scene.candidates));
      }
      if (scene.candidates == 1) wins++;
    }
    scene.reset();
    return wins / runs;
  }
}
