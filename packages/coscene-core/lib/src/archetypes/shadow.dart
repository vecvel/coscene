import '../level_spec.dart';
import '../scene.dart';

/// A lamp, a board and the shadow the board throws on the ground. The lamp
/// slides along a rail and may be raised; the board may slide too. The setup
/// wins when the shadow covers the painted patch exactly.
class ShadowScene extends Scene {
  ShadowScene(super.level) {
    final s = JsonReader(level.initialState, level.id, 'initialState.');
    final rules = JsonReader(level.validationRules, level.id, 'validationRules.');
    final lamp = s.object('lamp');
    lampX = Adjustable.fromJson(lamp.object('x'));
    lampHeight = Adjustable.fromJson(lamp.object('height'));
    final board = s.object('board');
    boardX = Adjustable.fromJson(board.object('x'));
    boardWidth = board.number('width');
    boardHeight = board.number('height');
    final t = s.object('target');
    targetFrom = t.number('from');
    targetTo = t.number('to');
    final g = s.objectOrNull('ground');
    groundMin = g?.number('min') ?? 0;
    groundMax = g?.number('max') ?? 100;
    tolerance = rules.number('edgeTolerance', orElse: 1);
    if (boardWidth <= 0 || targetTo <= targetFrom) {
      throw LevelFormatException('board and target need a positive width', levelId: level.id);
    }
    if (lampHeight.min <= boardHeight) {
      throw LevelFormatException('the lamp must always hang above the board', levelId: level.id);
    }
    if (controls.every((c) => c.isFixed)) {
      throw LevelFormatException('needs at least one part that moves', levelId: level.id);
    }
  }

  late final Adjustable lampX;
  late final Adjustable lampHeight;
  late final Adjustable boardX;
  late final double boardWidth;
  late final double boardHeight;
  late final double targetFrom;
  late final double targetTo;
  late final double groundMin;
  late final double groundMax;
  late final double tolerance;

  List<Adjustable> get controls => [lampX, lampHeight, boardX];

  double _project(double x) {
    final lx = lampX.value;
    final lh = lampHeight.value;
    return lx + (x - lx) * lh / (lh - boardHeight);
  }

  /// Left and right ends of the shadow on the ground.
  ({double from, double to}) get shadow => (from: _project(boardX.value), to: _project(boardX.value + boardWidth));

  @override
  void reset() {
    for (final c in controls) {
      c.reset();
    }
  }

  @override
  Map<String, dynamic> snapshot() => {
    'steps': [for (final c in controls) c.index],
  };

  @override
  void restore(Map<String, dynamic> snapshot) {
    final steps = (snapshot['steps'] as List).cast<int>();
    final cs = controls;
    if (steps.length != cs.length) throw ArgumentError('snapshot does not fit this level');
    for (var i = 0; i < cs.length; i++) {
      if (steps[i] < 0 || steps[i] >= cs[i].count) throw ArgumentError('snapshot step out of range');
      cs[i].index = steps[i];
    }
  }

  @override
  Outcome evaluate() {
    final sh = shadow;
    final detail = {'from': sh.from, 'to': sh.to};
    final dFrom = sh.from - targetFrom;
    final dTo = sh.to - targetTo;
    if (dFrom.abs() <= tolerance && dTo.abs() <= tolerance) return Outcome.solved(detail);
    final widthDiff = (sh.to - sh.from) - (targetTo - targetFrom);
    if (widthDiff.abs() > tolerance) {
      return Outcome.failed(widthDiff > 0 ? 'too_wide' : 'too_narrow', magnitude: widthDiff, detail: detail);
    }
    final shift = (dFrom + dTo) / 2;
    return Outcome.failed(shift < 0 ? 'off_left' : 'off_right', magnitude: shift, detail: detail);
  }

  @override
  SimResult simulate() {
    final b = TimelineBuilder(84);
    b.ramp('light', 0, 36);
    b.ramp('verdict', 40, 70);
    return SimResult(evaluate(), b.build());
  }
}

class ShadowArchetype extends Archetype {
  const ShadowArchetype();

  @override
  String get id => 'area_projection';

  @override
  ShadowScene create(LevelSpec level) => ShadowScene(level);

  void _enumerate(ShadowScene scene, void Function() visit) {
    final cs = scene.controls;
    void go(int k) {
      if (k == cs.length) {
        visit();
        return;
      }
      for (var i = 0; i < cs[k].count; i++) {
        cs[k].index = i;
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
    final moving = scene.controls.where((c) => !c.isFixed).length;
    return found == null ? null : Solution(found!, effort: moving);
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
