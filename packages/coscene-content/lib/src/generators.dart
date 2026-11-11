import 'dart:math' as math;

import 'package:coscene_core/coscene_core.dart';

import 'places.dart';

/// A level body proposed by a generator, before it is checked by the engine.
typedef Draft = ({Map<String, dynamic> state, Map<String, dynamic> rules, Map<String, dynamic> params, int minEffort});

typedef DraftBuilder = Draft? Function(Rng rng, int difficulty);

const Map<String, DraftBuilder> draftBuilders = {
  'balance_levers': _balance,
  'ray_reflection': _ray,
  'area_projection': _shadow,
  'volume_flow': _flow,
  'network_routing': _routing,
  'permutation_locks': _locks,
  'gear_ratio': _gears,
  'cargo_packing': _cargo,
};

LevelSpec _probe(String archetype, Map<String, dynamic> state, Map<String, dynamic> rules) => LevelSpec(
  id: 'probe',
  archetypeId: archetype,
  place: 0,
  index: 0,
  difficulty: 1,
  initialState: state,
  validationRules: rules,
  hints: const ['-'],
  i18nKey: '-',
  conceptId: '-',
);

double _round2(double v) => (v * 100).round() / 100;

/// Builds one level that the engine has loaded, solved and graded.
///
/// The same arguments always give the same level. Throws [StateError] when
/// no acceptable level turns up, which points at a generator bug.
LevelSpec generateLevel({
  required String id,
  required int place,
  required int index,
  required String archetypeId,
  required int difficulty,
  required int seed,
  Engine? engine,
  bool Function(LevelSpec level)? accept,
}) {
  final eng = engine ?? Engine.standard;
  final build = draftBuilders[archetypeId];
  final short = archetypeShortNames[archetypeId];
  if (build == null || short == null) {
    throw ArgumentError('no generator for archetype "$archetypeId"');
  }
  final tier = tierFor(difficulty);
  for (var attempt = 0; attempt < 6000; attempt++) {
    final draft = build(Rng(seed + attempt * 7919), difficulty);
    if (draft == null) continue;
    final level = LevelSpec(
      id: id,
      archetypeId: archetypeId,
      place: place,
      index: index,
      difficulty: difficulty,
      initialState: draft.state,
      validationRules: draft.rules,
      hints: [for (var h = 1; h <= 3; h++) 'hint.$short.$tier.$h'],
      i18nKey: 'scene.$short.$tier',
      conceptId: '${short}_$tier',
      textParams: draft.params,
    );
    final report = eng.inspect(level);
    if (!report.ok || report.solution!.effort < draft.minEffort) continue;
    if (accept != null && !accept(level)) continue;
    return level;
  }
  throw StateError('could not generate $archetypeId at difficulty $difficulty (seed $seed)');
}

// ---------------------------------------------------------------- balance

Draft? _balance(Rng r, int d) {
  final half = d <= 2 ? 4 : (d <= 5 ? 5 : 6);
  final nFixed = d <= 2 ? 1 : (d <= 5 ? r.range(1, 2) : r.range(2, 3));
  final nMovable = d <= 2 ? 1 : (d <= 4 ? 2 : (d <= 8 ? 3 : 4));
  final maxWeight = math.min(6, 2 + (d + 1) ~/ 2);
  final nBlocked = d >= 6 ? r.range(2, 3) : 0;
  final slots = [
    for (var s = -half; s <= half; s++)
      if (s != 0) s,
  ];
  r.shuffle(slots);
  final fixed = [
    for (var i = 0; i < nFixed; i++) {'weight': r.range(1, maxWeight), 'slot': slots[i]},
  ]..sort((a, b) => a['slot']!.compareTo(b['slot']!));
  final blocked = slots.sublist(nFixed, nFixed + nBlocked)..sort();
  final weights = [for (var i = 0; i < nMovable; i++) r.range(1, maxWeight)]..sort((a, b) => b.compareTo(a));
  // Past the first level, a single crate should not just mirror the fixed one.
  if (d > 1 && nFixed == 1 && nMovable == 1 && weights.first == fixed.first['weight']) return null;
  return (
    state: {
      'halfSpan': half,
      'fixed': fixed,
      'movable': [
        for (final w in weights) {'weight': w, 'slot': null},
      ],
      if (blocked.isNotEmpty) 'blocked': blocked,
    },
    rules: {'torqueTolerance': 0, 'requireAllPlaced': true},
    params: const {},
    minEffort: 1,
  );
}

// -------------------------------------------------------------------- ray

Draft? _ray(Rng r, int d) {
  final count = d <= 2 ? 1 : (d <= 5 ? 2 : 3);
  final step = d == 1 ? 30.0 : 15.0;
  final steps = (180 / step).round();
  final radius = d <= 3 ? 5.0 : 4.0;
  bool inside(Vec2 p, double margin) => p.x >= margin && p.x <= 100 - margin && p.y >= margin && p.y <= 100 - margin;

  final along = r.range(2, 8) * 10.0;
  final emitter = switch (r.nextInt(4)) {
    0 => Vec2(10, along),
    1 => Vec2(90, along),
    2 => Vec2(along, 10),
    _ => Vec2(along, 90),
  };
  final emitterDegrees = r.nextInt((360 / step).round()) * step;
  var dir = Vec2.fromDegrees(emitterDegrees);
  final toMiddle = (const Vec2(50, 50) - emitter).normalized;
  if (dir.dot(toMiddle) < 0.5) return null;

  var pos = emitter;
  final mirrors = <Map<String, dynamic>>[];
  final answer = <int>[];
  final keyPoints = <Vec2>[emitter];
  for (var k = 0; k < count; k++) {
    final c = pos + dir * r.range(22, 48).toDouble();
    if (!inside(c, 14)) return null;
    final options = <int>[];
    for (var s = 0; s < steps; s++) {
      final m = Vec2.fromDegrees(s * step);
      // Skip grazing mirrors and ones that send the beam straight back.
      if (dir.cross(m).abs() > 0.3 && dir.dot(m).abs() > 0.25) options.add(s);
    }
    if (options.isEmpty) return null;
    final s = r.pick(options);
    final m = Vec2.fromDegrees(s * step);
    dir = dir.reflect(m.perpendicular).normalized;
    final center = Vec2(_round2(c.x), _round2(c.y));
    mirrors.add({'x': center.x, 'y': center.y, 'length': 14, 'degrees': s * step, 'stepDegrees': step});
    answer.add(s);
    keyPoints.add(center);
    pos = center;
  }
  final end = pos + dir * r.range(22, 46).toDouble();
  if (!inside(end, 10)) return null;
  final target = Vec2(_round2(end.x), _round2(end.y));
  keyPoints.add(target);
  for (var i = 0; i < keyPoints.length; i++) {
    for (var j = i + 1; j < keyPoints.length; j++) {
      if (keyPoints[i].distanceTo(keyPoints[j]) < 17) return null;
    }
  }

  Map<String, dynamic> state(List<int> mirrorSteps, List<Map<String, dynamic>> walls) => {
    'size': 100,
    'emitter': {'x': emitter.x, 'y': emitter.y, 'degrees': emitterDegrees},
    'mirrors': [
      for (var i = 0; i < mirrors.length; i++) {...mirrors[i], 'degrees': mirrorSteps[i] * step},
    ],
    if (walls.isNotEmpty) 'walls': walls,
    'target': {'x': target.x, 'y': target.y, 'radius': radius},
  };
  final rules = {'hitTolerance': radius, 'minBounces': 0, 'maxBounces': 12};

  bool answerWorks(List<Map<String, dynamic>> walls) {
    final t = RayScene(_probe('ray_reflection', state(answer, walls), rules)).trace();
    return t.hit && t.bounces == count;
  }

  // True when some setup reaches the sensor without using every mirror.
  bool hasShortcut(List<Map<String, dynamic>> walls) {
    final scene = RayScene(_probe('ray_reflection', state(answer, walls), rules));
    var found = false;
    void go(int k) {
      if (found) return;
      if (k == count) {
        final t = scene.trace();
        if (t.hit && t.bounces < count) found = true;
        return;
      }
      for (var s = 0; s < steps; s++) {
        scene.mirrors[k].step = s;
        go(k + 1);
      }
    }

    go(0);
    return found;
  }

  if (!answerWorks(const [])) return null;

  final walls = <Map<String, dynamic>>[];
  if (d >= 6) {
    final wanted = d >= 8 ? 2 : 1;
    for (var tries = 0; tries < 40 && walls.length < wanted; tries++) {
      final c = Vec2(r.range(18, 82).toDouble(), r.range(18, 82).toDouble());
      if (keyPoints.any((p) => p.distanceTo(c) < 13)) continue;
      final half = Vec2.fromDegrees(r.nextInt(4) * 45.0, r.range(7, 11).toDouble());
      final a = c - half, b = c + half;
      final wall = {'x1': _round2(a.x), 'y1': _round2(a.y), 'x2': _round2(b.x), 'y2': _round2(b.y)};
      if (answerWorks([...walls, wall])) walls.add(wall);
    }
    if (walls.isEmpty) return null;
  }
  if (hasShortcut(walls)) return null;

  final start = [for (final s in answer) (s + r.range(1, steps - 1)) % steps];
  return (state: state(start, walls), rules: rules, params: const {}, minEffort: 1);
}

// ----------------------------------------------------------------- shadow

Draft? _shadow(Rng r, int d) {
  final boardWidth = r.pick([10.0, 12.0, 15.0, 20.0]);
  final boardHeight = r.pick([20.0, 25.0, 30.0]);
  final raise = d >= 3;
  final slideBoard = d >= 6;

  final heightMin = boardHeight + 20;
  final heightChoices = raise ? [for (var i = 0; i < 5; i++) heightMin + i * 10] : [boardHeight * 2];
  final lampXChoices = [for (var x = 10.0; x <= 90; x += 5) x];
  final boardXChoices = slideBoard ? [for (var x = 20.0; x <= 70; x += 5) x] : [r.range(6, 12) * 5.0];

  final lampX = r.pick(lampXChoices);
  final lampH = r.pick(heightChoices);
  final boardX = r.pick(boardXChoices);
  double project(double x) => lampX + (x - lampX) * lampH / (lampH - boardHeight);
  final from = _round2(project(boardX));
  final to = _round2(project(boardX + boardWidth));
  if (from < 3 || to > 97 || to - from > 60) return null;

  Map<String, dynamic> axis(List<double> choices, double value) => {
    'min': choices.first,
    'max': choices.last,
    'step': choices.length > 1 ? choices[1] - choices[0] : 1,
    'value': value,
  };
  return (
    state: {
      'lamp': {'x': axis(lampXChoices, r.pick(lampXChoices)), 'height': axis(heightChoices, r.pick(heightChoices))},
      'board': {'x': axis(boardXChoices, r.pick(boardXChoices)), 'width': boardWidth, 'height': boardHeight},
      'target': {'from': from, 'to': to},
      'ground': {'min': 0, 'max': 100},
    },
    rules: {'edgeTolerance': 0.75},
    params: const {},
    minEffort: 1,
  );
}

// ------------------------------------------------------------------- flow

Draft? _flow(Rng r, int d) {
  final count = d == 1 ? 1 : (d <= 3 ? 2 : 3);
  final widthPool = d == 1 ? [2] : (d == 2 ? [1, 2] : [1, 2, 3, 4]);
  final maxRate = d <= 2 ? 4 : (d <= 5 ? 5 : 6);
  final timed = d >= 6;
  final seconds = timed ? r.range(3, 7) : r.pick([4, 6]);

  final tanks = <Map<String, dynamic>>[];
  final rates = <int>[];
  final seenLevels = <double>{};
  for (var i = 0; i < count; i++) {
    final width = r.pick(widthPool);
    final rate = r.range(1, maxRate);
    final level = rate * seconds / width;
    if (level < 2 || level > 11 || (level * 2).roundToDouble() != level * 2) return null;
    seenLevels.add(level);
    rates.add(rate);
    tanks.add({'width': width, 'height': math.min(12, level.ceil() + r.range(1, 3)), 'target': level});
  }
  if (count > 1 && seenLevels.length == 1) return null;
  if (d >= 3 && tanks.map((t) => t['width']).toSet().length == 1) return null;

  final Map<String, dynamic> duration;
  if (timed) {
    final others = [
      for (var s = 2; s <= 8; s++)
        if (s != seconds) s,
    ];
    duration = {'min': 2, 'max': 8, 'step': 1, 'value': r.pick(others)};
  } else {
    duration = {'min': seconds, 'max': seconds, 'step': 1, 'value': seconds};
  }
  return (
    state: {
      'tanks': tanks,
      'valves': [
        for (var i = 0; i < count; i++) {'tank': i, 'max': maxRate, 'rate': 0},
      ],
      'duration': duration,
      if (d >= 7) 'supply': rates.fold<int>(0, (a, b) => a + b),
    },
    rules: {'levelTolerance': 0.25},
    params: const {},
    minEffort: 1,
  );
}

// ---------------------------------------------------------------- routing

class _Branch {
  _Branch(this.depth);
  final int depth;
  _Branch? left;
  _Branch? right;
  String id = '';
  String kind = 'switch';
  double x = 0;
}

Draft? _routing(Rng r, int d) {
  final junctionCount = d <= 1 ? 2 : (d <= 5 ? 3 : 4);
  final colorCount = d <= 1 ? 2 : (d <= 7 ? 3 : 4);
  final itemCount = d <= 2 ? 4 : (d <= 5 ? 5 : 6);
  final kinds = d <= 2
      ? ['filter', 'switch']
      : (d <= 5 ? ['filter', 'filter', 'switch'] : ['filter', 'filter', 'flip', 'switch']);
  const palette = ['coral', 'teal', 'mustard', 'slate'];
  final colors = palette.sublist(0, colorCount);

  // Grow a random tree of junctions at most three deep.
  final root = _Branch(0);
  final all = <_Branch>[root];
  final open = <(_Branch, bool)>[(root, true), (root, false)];
  while (all.length < junctionCount) {
    final grow = [
      for (final o in open)
        if (o.$1.depth < 2) o,
    ];
    if (grow.isEmpty) return null;
    final slot = r.pick(grow);
    open.remove(slot);
    final child = _Branch(slot.$1.depth + 1);
    if (slot.$2) {
      slot.$1.left = child;
    } else {
      slot.$1.right = child;
    }
    all.add(child);
    open.addAll([(child, true), (child, false)]);
  }
  for (var i = 0; i < all.length; i++) {
    all[i].id = 'j${i + 1}';
    all[i].kind = r.pick(kinds);
  }
  if (d >= 6 && !all.any((j) => j.kind == 'flip')) return null;
  if (!all.any((j) => j.kind == 'filter')) return null;

  // Lay leaves out evenly along the bottom, junctions above their children.
  final binCount = junctionCount + 1;
  final bins = <Map<String, dynamic>>[];
  final nodes = <Map<String, dynamic>>[];
  const depthY = [26.0, 48.0, 68.0];
  String leaf() {
    final k = bins.length;
    final id = 'b${k + 1}';
    bins.add({'id': id, 'kind': 'bin', 'x': _round2(12 + k * 76 / (binCount - 1)), 'y': 90, 'accepts': colors[0]});
    return id;
  }

  (String, double) place(_Branch? b) {
    if (b == null) {
      final id = leaf();
      return (id, bins.last['x'] as double);
    }
    final (leftId, leftX) = place(b.left);
    final (rightId, rightX) = place(b.right);
    b.x = _round2((leftX + rightX) / 2);
    nodes.add({
      'id': b.id,
      'kind': b.kind,
      'x': b.x,
      'y': depthY[b.depth],
      'left': leftId,
      'right': rightId,
      'state': 0,
    });
    return (b.id, b.x);
  }

  place(root);
  nodes.insert(0, {'id': 'in', 'kind': 'source', 'x': root.x, 'y': 6, 'next': root.id});

  final items = [for (var i = 0; i < itemCount; i++) r.pick(colors)];
  if (colors.any((c) => !items.contains(c))) return null;

  Map<String, dynamic> state(Map<String, int> states) => {
    'colors': colors,
    'items': items,
    'nodes': [
      for (final n in nodes)
        if (states.containsKey(n['id'])) {...n, 'state': states[n['id']]} else n,
      ...bins,
    ],
  };
  int stateCount(_Branch j) => j.kind == 'filter' ? colorCount : 2;

  // Pick the answer first, then label the bins to match where items land.
  final answer = {for (final j in all) j.id: r.nextInt(stateCount(j))};
  final trips = RoutingScene(_probe('network_routing', state(answer), const {})).run();
  final landed = <String, Set<String>>{};
  final visited = <String>{};
  for (final t in trips) {
    landed.putIfAbsent(t.bin, () => {}).add(t.color);
    visited.addAll(t.path);
  }
  if (landed.values.any((c) => c.length > 1) || landed.length < 2) return null;
  if (all.any((j) => !visited.contains(j.id))) return null;
  for (final b in bins) {
    b['accepts'] = landed[b['id']]?.first ?? r.pick(colors);
  }

  final start = {for (final j in all) j.id: r.nextInt(stateCount(j))};
  return (state: state(start), rules: const {'allSorted': true}, params: const {}, minEffort: 1);
}

// ------------------------------------------------------------------ locks

Draft? _locks(Rng r, int d) {
  final count = d <= 2 ? 2 : (d <= 8 ? 3 : 4);
  final positions = d == 1 ? 4 : (d <= 5 ? 6 : r.pick([6, 8]));
  final linkCount = d <= 2 ? 1 : (d <= 5 ? r.range(2, 3) : r.range(3, 5));
  final links = [
    for (var i = 0; i < count; i++) [for (var j = 0; j < count; j++) i == j ? 1 : 0],
  ];
  var placed = 0;
  for (var tries = 0; tries < 60 && placed < linkCount; tries++) {
    final i = r.nextInt(count), j = r.nextInt(count);
    if (i == j || links[i][j] != 0) continue;
    links[i][j] = d <= 3 ? 1 : r.pick([1, 1, -1]);
    placed++;
  }
  if (placed < linkCount) return null;

  // Scramble backwards from the open position, so it can always be reached.
  final values = List<int>.filled(count, 0);
  for (var m = 0; m < 4 + d; m++) {
    final i = r.nextInt(count);
    final delta = r.chance(0.5) ? 1 : -1;
    for (var j = 0; j < count; j++) {
      values[j] = (values[j] + links[i][j] * delta) % positions;
      if (values[j] < 0) values[j] += positions;
    }
  }
  return (
    state: {
      'dials': [
        for (final v in values) {'positions': positions, 'value': v, 'target': 0},
      ],
      'links': links,
    },
    rules: const {'allAligned': true},
    params: const {},
    minEffort: d <= 2 ? 2 : (d <= 5 ? 3 : 5),
  );
}

// ------------------------------------------------------------------ gears

const _teethPool = [8, 10, 12, 15, 16, 18, 20, 24, 30, 32, 36, 40, 48];

Draft? _gears(Rng r, int d) {
  // true marks a peg the player fills; false is a gear bolted in place.
  final layout = switch (d) {
    1 => [(false, true)],
    2 => [(true, false)],
    3 => [(false, true), (true, false)],
    4 || 5 => [(true, true), (true, false)],
    6 || 7 => [(true, true), (true, true)],
    _ => [(true, true), (true, false), (false, true)],
  };
  final slotCount = layout.fold<int>(0, (a, s) => a + (s.$1 ? 1 : 0) + (s.$2 ? 1 : 0));
  final trayCount = d <= 3 ? 4 : (d <= 5 ? 5 : 6);
  final pool = List<int>.of(_teethPool);
  r.shuffle(pool);
  final tray = pool.sublist(0, trayCount);
  final fixedPool = pool.sublist(trayCount);
  final answer = List<int>.generate(trayCount, (i) => i);
  r.shuffle(answer);

  var slot = 0;
  var fixed = 0;
  var num = 1, den = 1;
  final stages = <Map<String, dynamic>>[];
  Map<String, dynamic> spot(bool isSlot, void Function(int teeth) use) {
    if (isSlot) {
      use(tray[answer[slot]]);
      return {'slot': slot++};
    }
    final teeth = fixedPool[fixed++];
    use(teeth);
    return {'teeth': teeth};
  }

  for (final (driverSlot, drivenSlot) in layout) {
    final driver = spot(driverSlot, (t) => num *= t);
    final driven = spot(drivenSlot, (t) => den *= t);
    stages.add({'driver': driver, 'driven': driven});
  }
  final g = num.gcd(den);
  final turns = num ~/ g, crank = den ~/ g;
  if (turns == crank || turns > 8 || crank > 4) return null;
  final sizes = [...tray, ...fixedPool.sublist(0, fixed)];
  if (sizes.reduce(math.max) / sizes.reduce(math.min) > 5) return null;

  return (
    state: {
      'stages': stages,
      'tray': tray,
      'slots': List<int?>.filled(slotCount, null),
      'inputTurns': crank,
      'target': {'turns': turns},
    },
    rules: {'turnsTolerance': 0.001},
    params: {'turns': turns, 'crank': crank},
    minEffort: 1,
  );
}

// ------------------------------------------------------------------ cargo

Draft? _cargo(Rng r, int d) {
  final (cols, rows) = switch (d) {
    1 => (4, 2),
    2 => (4, 3),
    3 => (5, 3),
    4 || 5 => (6, 3),
    6 || 7 => (6, 4),
    _ => (7, 4),
  };
  // From difficulty 6 one square of the hold is blocked, so cut one extra.
  final wanted = switch (d) {
    1 => 3,
    2 || 3 => 4,
    4 || 5 => 5,
    6 || 7 => 7,
    _ => 8,
  };
  // Cut the hold into rectangles until there are enough small crates.
  final rects = <List<int>>[
    [0, 0, cols, rows],
  ];
  bool tooBig(List<int> q) => q[2] > 3 || q[3] > 3 || q[2] * q[3] > 6;
  while (rects.length < wanted || rects.any(tooBig)) {
    if (rects.length > wanted + 2) return null;
    final candidates = rects.where((q) => q[2] > 1 || q[3] > 1).toList()
      ..sort((a, b) => (b[2] * b[3]).compareTo(a[2] * a[3]));
    if (candidates.isEmpty) return null;
    final big = candidates.where(tooBig).toList();
    final q = big.isNotEmpty ? r.pick(big) : candidates.first;
    rects.remove(q);
    final vertical = q[3] == 1 || (q[2] > 1 && (q[2] > q[3] || (q[2] == q[3] && r.chance(0.5))));
    if (vertical) {
      final k = r.range(1, q[2] - 1);
      rects.add([q[0], q[1], k, q[3]]);
      rects.add([q[0] + k, q[1], q[2] - k, q[3]]);
    } else {
      final k = r.range(1, q[3] - 1);
      rects.add([q[0], q[1], q[2], k]);
      rects.add([q[0], q[1] + k, q[2], q[3] - k]);
    }
  }

  final blocked = <List<int>>[];
  if (d >= 6) {
    final singles = rects.where((q) => q[2] == 1 && q[3] == 1).toList();
    if (singles.isEmpty) return null;
    final q = r.pick(singles);
    rects.remove(q);
    blocked.add([q[0], q[1]]);
  }

  final balanced = d >= 3;
  final heavy = <List<int>>{};
  if (balanced) {
    final pool = rects.where((q) => q[2] * q[3] >= 2).toList();
    r.shuffle(pool);
    heavy.addAll(pool.take(d >= 6 ? 2 : 1));
    if (heavy.isEmpty) return null;
    var moment = 0.0;
    for (final q in rects) {
      moment += q[2] * q[3] * (heavy.contains(q) ? 3 : 1) * (q[0] + q[2] / 2 - cols / 2);
    }
    if (moment.abs() > 1.0) return null;
  }

  r.shuffle(rects);
  return (
    state: {
      'hold': {'cols': cols, 'rows': rows, if (blocked.isNotEmpty) 'blocked': blocked},
      'pieces': [
        for (final q in rects)
          {
            // Store each crate lying on its long side, so its outline gives
            // nothing away about how it fits.
            'w': math.max(q[2], q[3]),
            'h': math.min(q[2], q[3]),
            if (heavy.contains(q)) 'heavy': true,
          },
      ],
    },
    rules: {'requireAllLoaded': true, if (balanced) 'balanceTolerance': 1.0},
    params: const {},
    minEffort: 1,
  );
}
