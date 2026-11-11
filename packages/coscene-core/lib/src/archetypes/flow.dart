import '../level_spec.dart';
import '../scene.dart';

class FlowTank {
  FlowTank(this.width, this.height, this.target);

  /// How much water raises the level by one mark.
  final double width;
  final double height;

  /// The painted line the water must reach.
  final double target;
}

class FlowValve {
  FlowValve(this.tank, this.max, this.rate) : initialRate = rate;
  final int tank;
  final int max;
  final int initialRate;

  /// Notches open, 0 (shut) to [max].
  int rate;
}

/// Tanks filled through valves for a set time. Each tank's level ends at
/// flow times time divided by the tank's width. When the valves ask for more
/// than the pump can give, every valve gets its fair share.
class FlowScene extends Scene {
  FlowScene(super.level) {
    final s = JsonReader(level.initialState, level.id, 'initialState.');
    final rules = JsonReader(level.validationRules, level.id, 'validationRules.');
    for (final t in s.objects('tanks')) {
      tanks.add(FlowTank(t.number('width'), t.number('height'), t.number('target')));
    }
    for (final v in s.objects('valves')) {
      valves.add(FlowValve(v.integer('tank'), v.integer('max'), v.integer('rate', orElse: 0)));
    }
    duration = Adjustable.fromJson(s.object('duration'));
    supply = s.numberOrNull('supply');
    tolerance = rules.number('levelTolerance', orElse: 0.25);
    if (tanks.isEmpty || valves.isEmpty) {
      throw LevelFormatException('needs tanks and valves', levelId: level.id);
    }
    for (final t in tanks) {
      if (t.width <= 0 || t.height <= 0 || t.target <= 0 || t.target > t.height) {
        throw LevelFormatException('tank sizes and targets must be positive and fit', levelId: level.id);
      }
    }
    for (final v in valves) {
      if (v.tank < 0 || v.tank >= tanks.length || v.max < 1 || v.rate < 0 || v.rate > v.max) {
        throw LevelFormatException('valve does not fit its tank or range', levelId: level.id);
      }
    }
  }

  final List<FlowTank> tanks = [];
  final List<FlowValve> valves = [];
  late final Adjustable duration;
  late final double? supply;
  late final double tolerance;

  bool setRate(int valve, int rate) {
    final v = valves[valve];
    final next = rate.clamp(0, v.max);
    if (next == v.rate) return false;
    v.rate = next;
    return true;
  }

  /// Share of the asked-for flow each valve really gets.
  double get pressure {
    final asked = valves.fold<int>(0, (a, v) => a + v.rate);
    final cap = supply;
    return cap != null && asked > cap ? cap / asked : 1;
  }

  /// Where each tank's level would end, ignoring its rim.
  List<double> get levels {
    final p = pressure;
    final out = List<double>.filled(tanks.length, 0);
    for (final v in valves) {
      out[v.tank] += v.rate * p * duration.value / tanks[v.tank].width;
    }
    return out;
  }

  @override
  void reset() {
    for (final v in valves) {
      v.rate = v.initialRate;
    }
    duration.reset();
  }

  @override
  Map<String, dynamic> snapshot() => {
    'rates': [for (final v in valves) v.rate],
    'duration': duration.index,
  };

  @override
  void restore(Map<String, dynamic> snapshot) {
    final rates = (snapshot['rates'] as List).cast<int>();
    final d = snapshot['duration'] as int;
    if (rates.length != valves.length || d < 0 || d >= duration.count) {
      throw ArgumentError('snapshot does not fit this level');
    }
    for (var i = 0; i < valves.length; i++) {
      if (rates[i] < 0 || rates[i] > valves[i].max) throw ArgumentError('snapshot rate out of range');
      valves[i].rate = rates[i];
    }
    duration.index = d;
  }

  @override
  Outcome evaluate() {
    final ls = levels;
    final detail = {'levels': ls, 'pressure': pressure};
    var spill = 0.0;
    var worst = 0.0;
    for (var i = 0; i < tanks.length; i++) {
      final over = ls[i] - tanks[i].height;
      if (over > 1e-9 && over > spill) spill = over;
      final off = ls[i] - tanks[i].target;
      if (off.abs() > worst.abs()) worst = off;
    }
    if (spill > 0) return Outcome.failed('overflow', magnitude: spill, detail: detail);
    if (worst.abs() <= tolerance + 1e-9) return Outcome.solved(detail);
    return Outcome.failed(worst < 0 ? 'too_low' : 'too_high', magnitude: worst, detail: detail);
  }

  @override
  SimResult simulate() {
    final run = (duration.value * 18).round().clamp(40, 150);
    final b = TimelineBuilder(run + 40);
    b.fill('fill', (i) => (i / run).clamp(0.0, 1.0));
    b.ramp('verdict', run, run + 24);
    return SimResult(evaluate(), b.build());
  }
}

class FlowArchetype extends Archetype {
  const FlowArchetype();

  @override
  String get id => 'volume_flow';

  @override
  FlowScene create(LevelSpec level) => FlowScene(level);

  void _enumerate(FlowScene scene, void Function() visit) {
    void go(int k) {
      if (k == scene.valves.length) {
        for (var d = 0; d < scene.duration.count; d++) {
          scene.duration.index = d;
          visit();
        }
        return;
      }
      for (var r = 0; r <= scene.valves[k].max; r++) {
        scene.valves[k].rate = r;
        go(k + 1);
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
    return found == null ? null : Solution(found!, effort: scene.valves.length + (scene.duration.isFixed ? 0 : 1));
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
