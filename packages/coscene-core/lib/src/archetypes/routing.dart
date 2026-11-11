import '../level_spec.dart';
import '../scene.dart';
import '../vec2.dart';

enum RouteKind { source, switcher, flip, filter, bin }

const _kindNames = {
  'source': RouteKind.source,
  'switch': RouteKind.switcher,
  'flip': RouteKind.flip,
  'filter': RouteKind.filter,
  'bin': RouteKind.bin,
};

class RouteNode {
  RouteNode(
    this.id,
    this.kind,
    this.position, {
    this.next,
    this.left,
    this.right,
    this.accepts,
    this.state = 0,
    this.fixed = false,
  }) : initialState = state;
  final String id;
  final RouteKind kind;
  final Vec2 position;
  final String? next;
  final String? left;
  final String? right;

  /// For bins: the colour that belongs here.
  final String? accepts;
  final bool fixed;
  final int initialState;

  /// Switch: 0 sends left, 1 sends right. Flip: the side the next item
  /// takes, swapping after each one. Filter: index of the colour sent left.
  int state;

  bool get isJunction => kind == RouteKind.switcher || kind == RouteKind.flip || kind == RouteKind.filter;
}

/// Where one item went.
class RouteTrip {
  RouteTrip(this.color, this.path, this.bin, this.correct);
  final String color;
  final List<String> path;
  final String bin;
  final bool correct;
}

/// Belts carrying coloured items through junctions into bins. The setup
/// wins when every item lands in the bin of its own colour.
class RoutingScene extends Scene {
  RoutingScene(super.level) {
    final s = JsonReader(level.initialState, level.id, 'initialState.');
    colors = s.strings('colors');
    items = s.strings('items');
    for (final n in s.objects('nodes')) {
      final kind = _kindNames[n.string('kind')];
      if (kind == null) throw LevelFormatException('unknown node kind', levelId: level.id);
      final node = RouteNode(
        n.string('id'),
        kind,
        Vec2(n.number('x'), n.number('y')),
        next: n.stringOrNull('next'),
        left: n.stringOrNull('left'),
        right: n.stringOrNull('right'),
        accepts: n.stringOrNull('accepts'),
        state: n.integer('state', orElse: 0),
        fixed: n.boolean('fixed', orElse: false),
      );
      if (nodes.containsKey(node.id)) {
        throw LevelFormatException('duplicate node id ${node.id}', levelId: level.id);
      }
      nodes[node.id] = node;
    }
    _check();
  }

  late final List<String> colors;
  late final List<String> items;
  final Map<String, RouteNode> nodes = {};
  late final RouteNode source;

  int stateCount(RouteNode n) => n.kind == RouteKind.filter ? colors.length : 2;

  void _check() {
    Never fail(String m) => throw LevelFormatException(m, levelId: level.id);
    final sources = nodes.values.where((n) => n.kind == RouteKind.source).toList();
    if (sources.length != 1) fail('needs exactly one source');
    source = sources.single;
    if (items.isEmpty) fail('needs at least one item');
    if (items.any((c) => !colors.contains(c))) fail('item colour missing from "colors"');
    if (!nodes.values.any((n) => n.isJunction && !n.fixed)) fail('needs a junction the player can set');
    // Every path must end in a bin and never loop.
    final done = <String>{};
    void walk(String? id, Set<String> trail) {
      final node = nodes[id];
      if (node == null) fail('belt leads to a missing node "$id"');
      if (trail.contains(node.id)) fail('belts loop back on themselves');
      if (done.contains(node.id)) return;
      final next = {...trail, node.id};
      switch (node.kind) {
        case RouteKind.source:
          walk(node.next, next);
        case RouteKind.bin:
          if (node.accepts == null || !colors.contains(node.accepts)) fail('bin needs a known colour');
        default:
          if (node.state < 0 || node.state >= stateCount(node)) fail('junction state out of range');
          walk(node.left, next);
          walk(node.right, next);
      }
      done.add(node.id);
    }

    walk(source.id, {});
  }

  List<RouteNode> get junctions => [
    for (final n in nodes.values)
      if (n.isJunction) n,
  ];

  /// Steps a junction to its next setting. Returns false when it is fixed.
  bool cycle(String id) {
    final n = nodes[id];
    if (n == null || !n.isJunction || n.fixed) return false;
    n.state = (n.state + 1) % stateCount(n);
    return true;
  }

  /// Sends every item through in order and reports where each ended up.
  List<RouteTrip> run() {
    final flips = {
      for (final n in nodes.values)
        if (n.kind == RouteKind.flip) n.id: n.state,
    };
    final trips = <RouteTrip>[];
    for (final color in items) {
      final path = <String>[source.id];
      var node = nodes[source.next]!;
      while (node.isJunction) {
        path.add(node.id);
        final bool goLeft;
        switch (node.kind) {
          case RouteKind.switcher:
            goLeft = node.state == 0;
          case RouteKind.flip:
            goLeft = flips[node.id] == 0;
            flips[node.id] = 1 - flips[node.id]!;
          default:
            goLeft = colors[node.state] == color;
        }
        node = nodes[goLeft ? node.left : node.right]!;
      }
      path.add(node.id);
      trips.add(RouteTrip(color, path, node.id, node.accepts == color));
    }
    return trips;
  }

  @override
  void reset() {
    for (final n in nodes.values) {
      n.state = n.initialState;
    }
  }

  @override
  Map<String, dynamic> snapshot() => {
    'states': {for (final n in junctions) n.id: n.state},
  };

  @override
  void restore(Map<String, dynamic> snapshot) {
    final states = (snapshot['states'] as Map).cast<String, dynamic>();
    for (final n in junctions) {
      final v = states[n.id];
      if (v is! int || v < 0 || v >= stateCount(n)) throw ArgumentError('snapshot does not fit this level');
      if (n.fixed && v != n.initialState) throw ArgumentError('snapshot changes a fixed junction');
      n.state = v;
    }
  }

  Outcome _judge(List<RouteTrip> trips) {
    final wrong = trips.where((t) => !t.correct).length;
    final detail = {
      'bins': [for (final t in trips) t.bin],
      'correct': [for (final t in trips) t.correct],
    };
    return wrong == 0
        ? Outcome.solved(detail)
        : Outcome.failed('misplaced', magnitude: wrong.toDouble(), detail: detail);
  }

  @override
  Outcome evaluate() => _judge(run());

  @override
  SimResult simulate() {
    final trips = run();
    const gap = 38;
    const unitsPerFrame = 1.1;
    // Distance along its route at which each item reaches each node.
    final routes = <List<Vec2>>[];
    final marks = <List<double>>[];
    var longest = 0.0;
    for (final t in trips) {
      final pts = [for (final id in t.path) nodes[id]!.position];
      final d = <double>[0];
      for (var i = 1; i < pts.length; i++) {
        d.add(d.last + pts[i].distanceTo(pts[i - 1]));
      }
      routes.add(pts);
      marks.add(d);
      if (d.last > longest) longest = d.last;
    }
    final frames = ((trips.length - 1) * gap + longest / unitsPerFrame).ceil() + 44;
    final b = TimelineBuilder(frames);
    final flipFrames = <String, List<int>>{};
    for (var k = 0; k < trips.length; k++) {
      final pts = routes[k];
      final d = marks[k];
      final start = k * gap;
      final xs = b.track('x$k');
      final ys = b.track('y$k');
      final on = b.track('on$k');
      for (var f = 0; f < frames; f++) {
        final travelled = ((f - start) * unitsPerFrame).clamp(0.0, d.last);
        var seg = 1;
        while (seg < d.length - 1 && d[seg] < travelled) {
          seg++;
        }
        final span = d[seg] - d[seg - 1];
        final p = pts[seg - 1].lerp(pts[seg], span == 0 ? 1 : (travelled - d[seg - 1]) / span);
        xs[f] = p.x;
        ys[f] = p.y;
        on[f] = f >= start ? 1 : 0;
      }
      for (var i = 1; i < trips[k].path.length - 1; i++) {
        final node = nodes[trips[k].path[i]]!;
        if (node.kind == RouteKind.flip) {
          flipFrames.putIfAbsent(node.id, () => []).add(start + (d[i] / unitsPerFrame).round());
        }
      }
    }
    for (final n in nodes.values.where((n) => n.kind == RouteKind.flip)) {
      final toggles = flipFrames[n.id] ?? const <int>[];
      b.fill('flip:${n.id}', (f) {
        final count = toggles.where((t) => t <= f).length;
        return ((n.state + count) % 2).toDouble();
      });
    }
    b.ramp('verdict', frames - 40, frames - 16);
    return SimResult(_judge(trips), b.build());
  }
}

class RoutingArchetype extends Archetype {
  const RoutingArchetype();

  @override
  String get id => 'network_routing';

  @override
  RoutingScene create(LevelSpec level) => RoutingScene(level);

  void _enumerate(RoutingScene scene, void Function() visit) {
    final free = [
      for (final n in scene.junctions)
        if (!n.fixed) n,
    ];
    void go(int k) {
      if (k == free.length) {
        visit();
        return;
      }
      for (var s = 0; s < scene.stateCount(free[k]); s++) {
        free[k].state = s;
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
    final free = scene.junctions.where((n) => !n.fixed).length;
    return found == null ? null : Solution(found!, effort: free);
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
