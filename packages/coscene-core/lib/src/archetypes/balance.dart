import '../level_spec.dart';
import '../scene.dart';

/// A load that sits on the arm. Fixed loads never move.
class BalanceLoad {
  BalanceLoad(this.weight, this.slot, {required this.fixed}) : initialSlot = slot;
  final int weight;
  final bool fixed;
  final int? initialSlot;

  /// Signed distance from the middle in slots, or null while off the arm.
  int? slot;
}

/// An arm hanging from its middle. Loads pull it down on each side by
/// weight times distance. The setup wins when both sides pull equally.
class BalanceScene extends Scene {
  BalanceScene(super.level) {
    final s = JsonReader(level.initialState, level.id, 'initialState.');
    final rules = JsonReader(level.validationRules, level.id, 'validationRules.');
    halfSpan = s.integer('halfSpan');
    if (halfSpan < 1 || halfSpan > 8) {
      throw LevelFormatException('"halfSpan" must be 1 to 8', levelId: level.id);
    }
    blocked = s.integers('blocked', optional: true).toSet();
    for (final f in s.objects('fixed', optional: true)) {
      loads.add(BalanceLoad(f.integer('weight'), f.integer('slot'), fixed: true));
    }
    for (final m in s.objects('movable')) {
      loads.add(BalanceLoad(m.integer('weight'), m.integerOrNull('slot'), fixed: false));
    }
    tolerance = rules.number('torqueTolerance', orElse: 0);
    requireAll = rules.boolean('requireAllPlaced', orElse: true);
    final seen = <int>{};
    for (final l in loads) {
      if (l.weight < 1) throw LevelFormatException('weights must be positive', levelId: level.id);
      final slot = l.slot;
      if (slot == null) continue;
      if (!_slotExists(slot) || blocked.contains(slot) || !seen.add(slot)) {
        throw LevelFormatException('load starts on an invalid slot $slot', levelId: level.id);
      }
    }
    if (!loads.any((l) => !l.fixed)) {
      throw LevelFormatException('needs at least one movable load', levelId: level.id);
    }
  }

  late final int halfSpan;
  late final Set<int> blocked;
  late final double tolerance;
  late final bool requireAll;
  final List<BalanceLoad> loads = [];

  bool _slotExists(int slot) => slot != 0 && slot.abs() <= halfSpan;

  Iterable<int> get freeSlots sync* {
    for (var s = -halfSpan; s <= halfSpan; s++) {
      if (s != 0 && !blocked.contains(s) && !loads.any((l) => l.slot == s)) yield s;
    }
  }

  bool canPlace(int load, int slot) =>
      !loads[load].fixed &&
      _slotExists(slot) &&
      !blocked.contains(slot) &&
      !loads.any((l) => l.slot == slot && !identical(l, loads[load]));

  /// Puts a load on a slot, or lifts it off with null. Returns false when
  /// the move is not allowed.
  bool place(int load, int? slot) {
    if (loads[load].fixed) return false;
    if (slot != null && !canPlace(load, slot)) return false;
    loads[load].slot = slot;
    return true;
  }

  /// Net turning pull. Positive means the right side is heavier.
  int get torque {
    var t = 0;
    for (final l in loads) {
      final s = l.slot;
      if (s != null) t += l.weight * s;
    }
    return t;
  }

  int get unplaced => loads.where((l) => l.slot == null).length;

  @override
  void reset() {
    for (final l in loads) {
      l.slot = l.initialSlot;
    }
  }

  @override
  Map<String, dynamic> snapshot() => {
    'slots': [
      for (final l in loads)
        if (!l.fixed) l.slot,
    ],
  };

  @override
  void restore(Map<String, dynamic> snapshot) {
    final slots = (snapshot['slots'] as List).cast<int?>();
    final movable = [
      for (var i = 0; i < loads.length; i++)
        if (!loads[i].fixed) i,
    ];
    if (slots.length != movable.length) throw ArgumentError('snapshot does not fit this level');
    for (final i in movable) {
      loads[i].slot = null;
    }
    for (var k = 0; k < movable.length; k++) {
      final slot = slots[k];
      if (slot != null && !place(movable[k], slot)) {
        throw ArgumentError('snapshot puts a load on an invalid slot');
      }
    }
  }

  @override
  Outcome evaluate() {
    final t = torque;
    final detail = {'torque': t};
    if (requireAll && unplaced > 0) {
      return Outcome.failed('unplaced', magnitude: unplaced.toDouble(), detail: detail);
    }
    if (t.abs() <= tolerance) return Outcome.solved(detail);
    return Outcome.failed(t < 0 ? 'tips_left' : 'tips_right', magnitude: t.toDouble(), detail: detail);
  }

  @override
  SimResult simulate() {
    final outcome = evaluate();
    final b = TimelineBuilder(110);
    final t = torque;
    if (outcome.success) {
      b.spring('angle', target: 0, velocity: 0.35);
      b.ramp('lift', 45, 105);
    } else {
      // The further off, the further the arm drops before the stop catches it.
      final rest = t == 0 ? 0.0 : t.sign * (0.06 + 0.03 * t.abs()).clamp(0.0, 0.3);
      b.spring('angle', target: rest, omega: 8, damping: 0.22);
      b.fill('lift', (_) => 0);
    }
    return SimResult(outcome, b.build());
  }
}

class BalanceArchetype extends Archetype {
  const BalanceArchetype();

  @override
  String get id => 'balance_levers';

  @override
  BalanceScene create(LevelSpec level) => BalanceScene(level);

  /// Calls [visit] for every way of putting all movable loads on free slots.
  void _enumerate(BalanceScene scene, void Function() visit) {
    final movable = [
      for (var i = 0; i < scene.loads.length; i++)
        if (!scene.loads[i].fixed) i,
    ];
    for (final i in movable) {
      scene.loads[i].slot = null;
    }
    void go(int k) {
      if (k == movable.length) {
        visit();
        return;
      }
      for (final slot in scene.freeSlots.toList()) {
        scene.loads[movable[k]].slot = slot;
        go(k + 1);
        scene.loads[movable[k]].slot = null;
      }
    }

    go(0);
  }

  @override
  Solution? solve(LevelSpec level) {
    final scene = create(level);
    Map<String, dynamic>? found;
    _enumerate(scene, () {
      if (found == null && scene.evaluate().success) found = scene.snapshot();
    });
    final movable = scene.loads.where((l) => !l.fixed).length;
    return found == null ? null : Solution(found!, effort: movable);
  }

  @override
  double? winFraction(LevelSpec level) {
    final scene = create(level);
    var total = 0;
    var wins = 0;
    _enumerate(scene, () {
      total++;
      if (scene.evaluate().success) wins++;
    });
    return total == 0 ? 0 : wins / total;
  }
}
