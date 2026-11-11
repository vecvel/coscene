import '../level_spec.dart';
import '../scene.dart';

/// One place a gear sits: either a gear that is bolted on, or an empty peg
/// the player fills from the tray.
class GearSpot {
  const GearSpot.fixed(int teeth) : fixedTeeth = teeth, slot = null;
  const GearSpot.slot(int index) : fixedTeeth = null, slot = index;
  final int? fixedTeeth;
  final int? slot;
}

/// A pair of meshing gears. The driven gear shares its axle with the next
/// stage's driver.
class GearStage {
  const GearStage(this.driver, this.driven);
  final GearSpot driver;
  final GearSpot driven;
}

/// A crank, a train of gears and a hand that must turn an exact number of
/// times. Each meshing pair multiplies the speed by driver teeth over
/// driven teeth.
class GearScene extends Scene {
  GearScene(super.level) {
    final s = JsonReader(level.initialState, level.id, 'initialState.');
    final rules = JsonReader(level.validationRules, level.id, 'validationRules.');
    GearSpot spot(JsonReader r) {
      final teeth = r.integerOrNull('teeth');
      if (teeth != null) return GearSpot.fixed(teeth);
      return GearSpot.slot(r.integer('slot'));
    }

    for (final st in s.objects('stages')) {
      stages.add(GearStage(spot(st.object('driver')), spot(st.object('driven'))));
    }
    tray = s.integers('tray');
    final initial = s.list('slots');
    if (initial.any((e) => e != null && e is! int)) {
      throw LevelFormatException('"slots" must hold tray positions or null', levelId: level.id);
    }
    slots = initial.cast<int?>().toList();
    _initialSlots = List.of(slots);
    inputTurns = s.integer('inputTurns', orElse: 1);
    targetTurns = s.object('target').number('turns');
    tolerance = rules.number('turnsTolerance', orElse: 0.001);

    final used = <int>{};
    for (final st in stages) {
      for (final sp in [st.driver, st.driven]) {
        final teeth = sp.fixedTeeth;
        if (teeth != null && teeth < 4) throw LevelFormatException('gears need 4 or more teeth', levelId: level.id);
        final slot = sp.slot;
        if (slot != null && (slot < 0 || slot >= slots.length || !used.add(slot))) {
          throw LevelFormatException('each peg must be used exactly once', levelId: level.id);
        }
      }
    }
    if (stages.isEmpty || used.length != slots.length || slots.isEmpty) {
      throw LevelFormatException('needs stages and at least one empty peg', levelId: level.id);
    }
    if (tray.any((t) => t < 4) || tray.length < slots.length) {
      throw LevelFormatException('the tray needs enough gears', levelId: level.id);
    }
    final placed = slots.whereType<int>().toList();
    if (placed.any((i) => i < 0 || i >= tray.length) || placed.toSet().length != placed.length) {
      throw LevelFormatException('starting gears must come from the tray, once each', levelId: level.id);
    }
    if (inputTurns < 1 || targetTurns <= 0) {
      throw LevelFormatException('turn counts must be positive', levelId: level.id);
    }
  }

  final List<GearStage> stages = [];
  late final List<int> tray;

  /// For each peg, the tray position of the gear on it, or null when empty.
  late final List<int?> slots;
  late final List<int?> _initialSlots;
  late final int inputTurns;
  late final double targetTurns;
  late final double tolerance;

  int? teethAt(GearSpot spot) {
    final fixed = spot.fixedTeeth;
    if (fixed != null) return fixed;
    final i = slots[spot.slot!];
    return i == null ? null : tray[i];
  }

  /// Which peg a tray gear is on, or null while it is still in the tray.
  int? slotOf(int trayIndex) {
    final i = slots.indexOf(trayIndex);
    return i < 0 ? null : i;
  }

  /// Puts a tray gear on a peg (taking it off any other peg), or clears the
  /// peg with null.
  void assign(int slot, int? trayIndex) {
    if (trayIndex != null) {
      final other = slotOf(trayIndex);
      if (other != null) slots[other] = null;
    }
    slots[slot] = trayIndex;
  }

  /// Turns of each axle per turn of the crank. Axles after a missing gear
  /// stand still. Sign shows direction.
  List<double> get speeds {
    final out = <double>[1];
    var broken = false;
    for (final st in stages) {
      final a = teethAt(st.driver);
      final b = teethAt(st.driven);
      if (broken || a == null || b == null) {
        broken = true;
        out.add(0);
      } else {
        out.add(-out.last * a / b);
      }
    }
    return out;
  }

  int get emptySlots => slots.where((s) => s == null).length;

  @override
  void reset() {
    for (var i = 0; i < slots.length; i++) {
      slots[i] = _initialSlots[i];
    }
  }

  @override
  Map<String, dynamic> snapshot() => {'slots': List<int?>.of(slots)};

  @override
  void restore(Map<String, dynamic> snapshot) {
    final next = (snapshot['slots'] as List).cast<int?>();
    final placed = next.whereType<int>().toList();
    if (next.length != slots.length ||
        placed.any((i) => i < 0 || i >= tray.length) ||
        placed.toSet().length != placed.length) {
      throw ArgumentError('snapshot does not fit this level');
    }
    for (var i = 0; i < slots.length; i++) {
      slots[i] = next[i];
    }
  }

  @override
  Outcome evaluate() {
    final sp = speeds;
    final detail = {'speeds': sp};
    if (emptySlots > 0) {
      return Outcome.failed('missing_gear', magnitude: emptySlots.toDouble(), detail: detail);
    }
    final turns = sp.last.abs() * inputTurns;
    final diff = turns - targetTurns;
    if (diff.abs() <= tolerance) return Outcome.solved(detail);
    return Outcome.failed(diff > 0 ? 'too_fast' : 'too_slow', magnitude: diff, detail: detail);
  }

  @override
  SimResult simulate() {
    final run = (inputTurns * 54 + 30).clamp(70, 200);
    final b = TimelineBuilder(run + 36);
    b.fill('crank', (i) {
      final t = (i / run).clamp(0.0, 1.0);
      return inputTurns * t * t * (3 - 2 * t);
    });
    b.ramp('verdict', run, run + 24);
    return SimResult(evaluate(), b.build());
  }
}

class GearArchetype extends Archetype {
  const GearArchetype();

  @override
  String get id => 'gear_ratio';

  @override
  GearScene create(LevelSpec level) => GearScene(level);

  void _enumerate(GearScene scene, void Function() visit) {
    for (var i = 0; i < scene.slots.length; i++) {
      scene.slots[i] = null;
    }
    final used = List<bool>.filled(scene.tray.length, false);
    void go(int k) {
      if (k == scene.slots.length) {
        visit();
        return;
      }
      for (var t = 0; t < scene.tray.length; t++) {
        if (used[t]) continue;
        used[t] = true;
        scene.slots[k] = t;
        go(k + 1);
        scene.slots[k] = null;
        used[t] = false;
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
    return found == null ? null : Solution(found!, effort: scene.slots.length);
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
