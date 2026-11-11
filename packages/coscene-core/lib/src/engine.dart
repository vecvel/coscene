import 'archetypes/balance.dart';
import 'archetypes/cargo.dart';
import 'archetypes/flow.dart';
import 'archetypes/gears.dart';
import 'archetypes/locks.dart';
import 'archetypes/ray.dart';
import 'archetypes/routing.dart';
import 'archetypes/shadow.dart';
import 'level_spec.dart';
import 'scene.dart';

/// Bumped when levels made for this engine would not play on older ones.
/// Packs state the oldest engine they need.
const int engineVersion = 1;

/// What the engine found when it checked a level end to end.
class LevelReport {
  LevelReport(this.level, this.issues, {this.solution, this.winFraction});
  final LevelSpec level;

  /// Empty when the level is fit to ship.
  final List<String> issues;
  final Solution? solution;
  final double? winFraction;

  bool get ok => issues.isEmpty;
}

/// Knows every archetype and turns level data into playable scenes. It
/// holds no level-specific code: new levels need no engine changes.
class Engine {
  Engine(Iterable<Archetype> archetypes) : _archetypes = {for (final a in archetypes) a.id: a};

  static final Engine standard = Engine(const [
    BalanceArchetype(),
    RayArchetype(),
    ShadowArchetype(),
    FlowArchetype(),
    RoutingArchetype(),
    LockArchetype(),
    GearArchetype(),
    CargoArchetype(),
  ]);

  /// A level that random setups solve more often than this is too easy to
  /// stumble through.
  static const double maxWinFraction = 0.34;

  final Map<String, Archetype> _archetypes;

  Iterable<String> get archetypeIds => _archetypes.keys;
  bool supports(String archetypeId) => _archetypes.containsKey(archetypeId);

  Archetype archetype(String id) => _archetypes[id] ?? (throw LevelFormatException('unknown archetype "$id"'));

  Scene createScene(LevelSpec level) => archetype(level.archetypeId).create(level);
  Solution? solve(LevelSpec level) => archetype(level.archetypeId).solve(level);

  /// Loads, solves and grades a level. Never throws.
  LevelReport inspect(LevelSpec level) {
    final issues = <String>[];
    Solution? solution;
    double? fraction;
    try {
      final a = archetype(level.archetypeId);
      final scene = a.create(level);
      if (scene.evaluate().success) issues.add('starts already solved');
      solution = a.solve(level);
      if (solution == null) {
        issues.add('no winning setup exists');
      } else {
        scene.restore(solution.state);
        if (!scene.evaluate().success) issues.add('solver result does not pass validation');
        scene.reset();
        if (scene.evaluate().success) issues.add('reset does not restore the start');
      }
      fraction = a.winFraction(level);
      if (fraction != null && fraction > maxWinFraction) {
        issues.add('too easy: ${(fraction * 100).round()}% of setups win');
      }
    } on LevelFormatException catch (e) {
      issues.add(e.message);
    } catch (e) {
      issues.add('engine error: $e');
    }
    return LevelReport(level, issues, solution: solution, winFraction: fraction);
  }
}

/// Stars for a solved level. No timers: only failed tries and hints count.
int starsFor({required int failedAttempts, required int hintsUsed}) {
  if (failedAttempts <= 1 && hintsUsed == 0) return 3;
  if (failedAttempts <= 3 && hintsUsed <= 1) return 2;
  return 1;
}

/// One sitting with one level: the submission loop the app drives.
///
/// The player changes the scene freely, then calls [submit]. Nothing is
/// judged until then.
class PlaySession {
  PlaySession(this.engine, this.level) : scene = engine.createScene(level);

  final Engine engine;
  final LevelSpec level;
  final Scene scene;

  int attempts = 0;
  int failedAttempts = 0;
  int hintsUsed = 0;
  bool solved = false;

  /// The setup of the last failed try, shown as a faint outline.
  Map<String, dynamic>? ghost;
  Outcome? lastOutcome;

  /// Tests the current setup. A solved session stays solved.
  SimResult submit() {
    final result = scene.simulate();
    attempts++;
    lastOutcome = result.outcome;
    if (result.outcome.success) {
      solved = true;
    } else {
      failedAttempts++;
      ghost = scene.snapshot();
    }
    return result;
  }

  bool get hasMoreHints => hintsUsed < level.hints.length;

  /// Dictionary key of the next hint, or null when all have been shown.
  String? revealHint() => hasMoreHints ? level.hints[hintsUsed++] : null;

  List<String> get shownHints => level.hints.sublist(0, hintsUsed);

  void reset() => scene.reset();

  int get stars => solved ? starsFor(failedAttempts: failedAttempts, hintsUsed: hintsUsed) : 0;
}
