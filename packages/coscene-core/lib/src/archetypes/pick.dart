import '../level_spec.dart';
import '../scene.dart';

/// One tile the player can select. [w] is a weight (knapsack) and [s]..[e]
/// a time span (intervals); other rules only read [v].
class PickTile {
  const PickTile(this.v, {this.w = 0, this.s = 0, this.e = 0});

  factory PickTile.fromJson(JsonReader r) => PickTile(
    r.integer('v'),
    w: r.integer('w', orElse: 0),
    s: r.integer('s', orElse: 0),
    e: r.integer('e', orElse: 0),
  );

  final int v;
  final int w;
  final int s;
  final int e;
}

/// Select tiles that satisfy a rule:
///
/// * `sum`: values add up to `target` (with exactly `count` tiles if given)
/// * `xor`: values XOR to `target` (with exactly `count` tiles if given)
/// * `window`: `k` neighbouring tiles with the largest possible sum
/// * `intervals`: as many spans as possible with no two overlapping
/// * `knapsack`: weights within `cap` and the largest possible total value
class PickScene extends Scene {
  PickScene(super.level) {
    final s = JsonReader(level.initialState, level.id, 'initialState.');
    tiles.addAll(s.objects('tiles').map(PickTile.fromJson));
    layout = s.string('layout', orElse: 'row');
    final r = JsonReader(level.validationRules, level.id, 'validationRules.');
    rule = r.string('rule');
    target = r.integer('target', orElse: 0);
    count = r.integerOrNull('count');
    k = r.integer('k', orElse: 0);
    cap = r.integer('cap', orElse: 0);
    best = r.integer('best', orElse: 0);
    if (tiles.length < 2 || tiles.length > 16) {
      throw LevelFormatException('needs 2 to 16 tiles', levelId: level.id);
    }
    if (!const {'sum', 'xor', 'window', 'intervals', 'knapsack'}.contains(rule)) {
      throw LevelFormatException('pick rule "$rule" is not known', levelId: level.id);
    }
    if (rule == 'window' && (k < 1 || k > tiles.length)) {
      throw LevelFormatException('a window needs 1 <= k <= tiles', levelId: level.id);
    }
    if (rule == 'intervals' && tiles.any((t) => t.e <= t.s)) {
      throw LevelFormatException('every span must end after it starts', levelId: level.id);
    }
  }

  final List<PickTile> tiles = [];

  /// How the tiles are drawn: `row`, `bits`, `bars` or `items`.
  late final String layout;
  late final String rule;
  late final int target;
  late final int? count;
  late final int k;
  late final int cap;
  late final int best;

  final Set<int> picked = {};

  void toggle(int i) => picked.contains(i) ? picked.remove(i) : picked.add(i);

  @override
  void reset() => picked.clear();

  @override
  Map<String, dynamic> snapshot() => {'picked': picked.toList()..sort()};

  @override
  void restore(Map<String, dynamic> snapshot) {
    final list = (snapshot['picked'] as List).cast<int>();
    if (list.any((i) => i < 0 || i >= tiles.length)) throw ArgumentError('snapshot tile out of range');
    picked
      ..clear()
      ..addAll(list);
  }

  /// The number that matters for the rule, from the current selection.
  int get total => switch (rule) {
    'xor' => picked.fold(0, (a, i) => a ^ tiles[i].v),
    'intervals' => picked.length,
    _ => picked.fold(0, (a, i) => a + tiles[i].v),
  };

  int get weight => picked.fold(0, (a, i) => a + tiles[i].w);

  Outcome judge(Set<int> sel) {
    final saved = {...picked};
    picked
      ..clear()
      ..addAll(sel);
    final o = evaluate();
    picked
      ..clear()
      ..addAll(saved);
    return o;
  }

  @override
  Outcome evaluate() {
    if (picked.isEmpty) return const Outcome.failed('empty');
    final c = count;
    if (c != null && picked.length != c) {
      return Outcome.failed('wrong_count', magnitude: (picked.length - c).abs().toDouble(), detail: {'count': c});
    }
    final t = total;
    switch (rule) {
      case 'sum':
        if (t == target) return Outcome.solved({'total': t});
        return Outcome.failed(
          t > target ? 'too_much' : 'too_little',
          magnitude: (t - target).abs().toDouble(),
          detail: {'total': t},
        );
      case 'xor':
        if (t == target) return Outcome.solved({'total': t});
        return Outcome.failed('wrong_xor', detail: {'total': t});
      case 'window':
        final sorted = picked.toList()..sort();
        if (sorted.length != k) return Outcome.failed('wrong_count', detail: {'count': k});
        if (sorted.last - sorted.first != k - 1) return const Outcome.failed('not_together');
        if (t < best) return Outcome.failed('not_best', magnitude: (best - t).toDouble(), detail: {'total': t});
        return Outcome.solved({'total': t});
      case 'intervals':
        final spans = [for (final i in picked) tiles[i]]..sort((a, b) => a.s.compareTo(b.s));
        for (var i = 1; i < spans.length; i++) {
          if (spans[i].s < spans[i - 1].e) return const Outcome.failed('overlap');
        }
        if (t < best) return Outcome.failed('not_best', magnitude: (best - t).toDouble(), detail: {'total': t});
        return Outcome.solved({'total': t});
      default: // knapsack
        if (weight > cap) {
          return Outcome.failed('over_cap', magnitude: (weight - cap).toDouble(), detail: {'weight': weight});
        }
        if (t < best) return Outcome.failed('not_best', magnitude: (best - t).toDouble(), detail: {'total': t});
        return Outcome.solved({'total': t});
    }
  }

  @override
  SimResult simulate() {
    final outcome = evaluate();
    final b = TimelineBuilder(46);
    b.ramp('count', 2, 26);
    if (outcome.success) {
      b.spring('pop', target: 1, omega: 12, damping: 0.4, delay: 24);
    } else {
      b.spring('shake', target: 0, velocity: 6, omega: 32, damping: 0.15, delay: 24);
    }
    return SimResult(outcome, b.build());
  }
}

class PickArchetype extends Archetype {
  const PickArchetype();

  @override
  String get id => 'pick';

  @override
  PickScene create(LevelSpec level) => PickScene(level);

  /// Every winning selection, as bit masks over the tiles.
  static List<int> winners(PickScene scene) {
    final n = scene.tiles.length;
    final out = <int>[];
    for (var mask = 1; mask < (1 << n); mask++) {
      final sel = {
        for (var i = 0; i < n; i++)
          if (mask & (1 << i) != 0) i,
      };
      if (scene.judge(sel).success) out.add(mask);
    }
    return out;
  }

  /// The best value any selection can reach, for the rules that optimise.
  static int bestPossible(PickScene scene) {
    final n = scene.tiles.length;
    var top = 0;
    for (var mask = 1; mask < (1 << n); mask++) {
      final sel = [
        for (var i = 0; i < n; i++)
          if (mask & (1 << i) != 0) i,
      ];
      switch (scene.rule) {
        case 'window':
          if (sel.length != scene.k || sel.last - sel.first != scene.k - 1) continue;
          top = [top, sel.fold(0, (a, i) => a + scene.tiles[i].v)].reduce((a, b) => a > b ? a : b);
        case 'intervals':
          final spans = [for (final i in sel) scene.tiles[i]]..sort((a, b) => a.s.compareTo(b.s));
          var ok = true;
          for (var j = 1; j < spans.length; j++) {
            if (spans[j].s < spans[j - 1].e) ok = false;
          }
          if (ok && sel.length > top) top = sel.length;
        case 'knapsack':
          if (sel.fold(0, (a, i) => a + scene.tiles[i].w) > scene.cap) continue;
          final v = sel.fold(0, (a, i) => a + scene.tiles[i].v);
          if (v > top) top = v;
      }
    }
    return top;
  }

  @override
  Solution? solve(LevelSpec level) {
    final scene = create(level);
    if (const {'window', 'intervals', 'knapsack'}.contains(scene.rule) && bestPossible(scene) != scene.best) {
      return null;
    }
    final wins = winners(scene);
    if (wins.isEmpty) return null;
    final mask = wins.first;
    final picked = [
      for (var i = 0; i < scene.tiles.length; i++)
        if (mask & (1 << i) != 0) i,
    ];
    return Solution({'picked': picked}, effort: picked.length);
  }

  @override
  double? winFraction(LevelSpec level) {
    final scene = create(level);
    return winners(scene).length / ((1 << scene.tiles.length) - 1);
  }
}
