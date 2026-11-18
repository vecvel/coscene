import '../level_spec.dart';
import '../scene.dart';

/// Draw the cheapest path across a grid, one step to a side neighbour at a
/// time. A cell costs its number to enter (1 everywhere on unweighted grids);
/// -1 is a wall. The path wins only when no cheaper one exists.
class RouteScene extends Scene {
  RouteScene(super.level) {
    final s = JsonReader(level.initialState, level.id, 'initialState.');
    cols = s.integer('cols');
    rows = s.integer('rows');
    cells = s.integers('cells');
    final st = s.integers('start'), go = s.integers('goal');
    if (cols < 2 ||
        rows < 2 ||
        cols > 9 ||
        rows > 9 ||
        cells.length != cols * rows ||
        st.length != 2 ||
        go.length != 2) {
      throw LevelFormatException('needs a 2x2 to 9x9 grid with a start and a goal', levelId: level.id);
    }
    start = st[1] * cols + st[0];
    goal = go[1] * cols + go[0];
    if (cells[start] < 0 || cells[goal] < 0 || start == goal) {
      throw LevelFormatException('start and goal must be open, different cells', levelId: level.id);
    }
    best = JsonReader(level.validationRules, level.id, 'validationRules.').integer('best');
    reset();
  }

  late final int cols;
  late final int rows;
  late final List<int> cells;
  late final int start;
  late final int goal;
  late final int best;

  /// Cells on the path so far, starting at [start].
  final List<int> path = [];

  @override
  void reset() {
    path
      ..clear()
      ..add(start);
  }

  bool neighbours(int a, int b) {
    final ac = a % cols, ar = a ~/ cols, bc = b % cols, br = b ~/ cols;
    return (ac - bc).abs() + (ar - br).abs() == 1;
  }

  /// Extends the path into [cell], or backs up to it if it is already on the
  /// path. Returns false when the step is not allowed.
  bool stepTo(int cell) {
    if (cell < 0 || cell >= cells.length || cells[cell] < 0) return false;
    final at = path.indexOf(cell);
    if (at >= 0) {
      if (at == path.length - 1) return false;
      path.removeRange(at + 1, path.length);
      return true;
    }
    if (path.last == goal || !neighbours(path.last, cell)) return false;
    path.add(cell);
    return true;
  }

  int get cost => path.skip(1).fold(0, (a, c) => a + cells[c]);

  @override
  Map<String, dynamic> snapshot() => {
    'path': [...path],
  };

  @override
  void restore(Map<String, dynamic> snapshot) {
    final list = (snapshot['path'] as List).cast<int>();
    reset();
    if (list.isEmpty || list.first != start) throw ArgumentError('a path starts at the start');
    for (final c in list.skip(1)) {
      if (!stepTo(c)) throw ArgumentError('snapshot path is not connected');
    }
  }

  @override
  Outcome evaluate() {
    if (path.last != goal) return const Outcome.failed('unfinished');
    final c = cost;
    if (c > best) return Outcome.failed('longer', magnitude: (c - best).toDouble(), detail: {'cost': c, 'best': best});
    return Outcome.solved({'cost': c});
  }

  @override
  SimResult simulate() {
    final outcome = evaluate();
    final steps = path.length;
    final b = TimelineBuilder(20 + steps * 4);
    b.fill('walk', (i) => (i / 4).clamp(0, steps - 1).toDouble());
    if (outcome.success) {
      b.spring('pop', target: 1, omega: 12, damping: 0.4, delay: steps * 4);
    } else {
      b.spring('shake', target: 0, velocity: 6, omega: 32, damping: 0.15, delay: steps * 4);
    }
    return SimResult(outcome, b.build());
  }
}

class RouteArchetype extends Archetype {
  const RouteArchetype();

  @override
  String get id => 'route';

  @override
  RouteScene create(LevelSpec level) => RouteScene(level);

  /// Cheapest path from start to goal (Dijkstra), or null when walled off.
  static List<int>? cheapest(RouteScene scene) {
    final n = scene.cells.length;
    const inf = 1 << 30;
    final dist = List<int>.filled(n, inf), prev = List<int>.filled(n, -1);
    final done = List<bool>.filled(n, false);
    dist[scene.start] = 0;
    for (;;) {
      var u = -1;
      for (var i = 0; i < n; i++) {
        if (!done[i] && dist[i] < inf && (u < 0 || dist[i] < dist[u])) u = i;
      }
      if (u < 0) break;
      done[u] = true;
      final c = u % scene.cols, r = u ~/ scene.cols;
      for (final (dc, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nc = c + dc, nr = r + dr;
        if (nc < 0 || nr < 0 || nc >= scene.cols || nr >= scene.rows) continue;
        final v = nr * scene.cols + nc;
        if (scene.cells[v] < 0) continue;
        final d = dist[u] + scene.cells[v];
        if (d < dist[v]) {
          dist[v] = d;
          prev[v] = u;
        }
      }
    }
    if (dist[scene.goal] == inf) return null;
    final path = <int>[];
    for (var v = scene.goal; v != -1; v = prev[v]) {
      path.add(v);
    }
    return path.reversed.toList();
  }

  @override
  Solution? solve(LevelSpec level) {
    final scene = create(level);
    final path = cheapest(scene);
    if (path == null) return null;
    scene.restore({'path': path});
    if (scene.cost != scene.best) return null;
    return Solution({'path': path}, effort: path.length - 1);
  }

  @override
  double? winFraction(LevelSpec level) => null;
}
