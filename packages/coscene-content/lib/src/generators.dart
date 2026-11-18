import 'dart:math' as math;

import 'package:coscene_core/coscene_core.dart';

/// A level body proposed by a generator, before it is checked by the engine.
///
/// [variant] names the kind of question within the topic and picks the
/// objective text, `scene.<topic>.<variant>.objective`.
typedef Draft = ({
  String archetype,
  String variant,
  Map<String, dynamic> state,
  Map<String, dynamic> rules,
  Map<String, dynamic> params,
});

/// Builds a draft for a topic. [step] is 0, 1 or 2 within the tier and [index]
/// is the scene's place in its topic (1 to 10), used to vary the questions.
typedef DraftBuilder = Draft? Function(Rng r, int step, int index);

/// Builds one level that the engine has loaded, solved and graded.
///
/// The same arguments always give the same level. Throws [StateError] when
/// no acceptable level turns up, which points at a generator bug.
LevelSpec generateLevel({
  required String id,
  required int place,
  required int index,
  required String topic,
  required int difficulty,
  required int seed,
  Engine? engine,
  bool Function(LevelSpec level)? accept,
}) {
  final eng = engine ?? Engine.standard;
  final build = topicBuilders[topic];
  if (build == null) throw ArgumentError('no generator for topic "$topic"');
  final step = (difficulty - 1) % 3;
  for (var attempt = 0; attempt < 4000; attempt++) {
    final draft = build(Rng(seed + attempt * 7919), step, index);
    if (draft == null) continue;
    final level = LevelSpec(
      id: id,
      archetypeId: draft.archetype,
      place: place,
      index: index,
      difficulty: difficulty,
      initialState: draft.state,
      validationRules: draft.rules,
      hints: [for (var h = 1; h <= 3; h++) 'hint.$topic.$h'],
      i18nKey: 'scene.$topic.${draft.variant}',
      conceptId: topic,
      textParams: draft.params,
    );
    final report = eng.inspect(level);
    if (!report.ok) continue;
    if (accept != null && !accept(level)) continue;
    return level;
  }
  throw StateError('could not generate $topic at difficulty $difficulty (seed $seed)');
}

const Map<String, DraftBuilder> topicBuilders = {
  'binary': _binary,
  'bitwise': _bitwise,
  'logic': _logic,
  'logarithms': _logarithms,
  'counting': _counting,
  'modulo': _modulo,
  'binary_search': _binarySearch,
  'two_pointers': _twoPointers,
  'stacks': _stacks,
  'queues': _queues,
  'bit_tricks': _bitTricks,
  'sorting': _sorting,
  'hashing': _hashing,
  'recursion': _recursion,
  'sliding_window': _slidingWindow,
  'prefix_sums': _prefixSums,
  'greedy': _greedy,
  'heaps': _heaps,
  'bfs': _bfs,
  'combinatorics': _combinatorics,
  'dynamic_programming': _dynamicProgramming,
  'knapsack': _knapsack,
  'shortest_paths': _shortestPaths,
  'topological_sort': _topologicalSort,
  'search_the_answer': _searchTheAnswer,
  'xor_tricks': _xorTricks,
  'union_find': _unionFind,
  'probability': _probability,
  'caching': _caching,
  'rate_limiting': _rateLimiting,
};

// ------------------------------------------------------------------ helpers

Map<String, dynamic> _expr(String text, {String label = ''}) => {
  'kind': 'expr',
  'text': text,
  if (label.isNotEmpty) 'label': label,
};

Map<String, dynamic> _cells(List<Object> values, {String label = '', bool index = false, List<int> mark = const []}) =>
    {
      'kind': 'cells',
      'cells': [for (final v in values) '$v'],
      if (label.isNotEmpty) 'label': label,
      if (index) 'index': true,
      if (mark.isNotEmpty) 'mark': mark,
    };

Map<String, dynamic> _bits(int value, int width, {String label = ''}) => {
  'kind': 'bits',
  'cells': [for (var i = width - 1; i >= 0; i--) '${(value >> i) & 1}'],
  if (label.isNotEmpty) 'label': label,
};

Map<String, dynamic> _number(int max, {String label = ''}) => {
  'mode': 'number',
  'max': max,
  if (label.isNotEmpty) 'label': label,
};

Map<String, dynamic> _bool(String label) => {'mode': 'bool', 'label': label};

Draft _answer(
  String variant,
  List<Map<String, dynamic>> board,
  List<Map<String, dynamic>> fields,
  List<int> answers, [
  Map<String, dynamic> params = const {},
]) => (
  archetype: 'answer',
  variant: variant,
  state: {'board': board, 'fields': fields},
  rules: {'answers': answers},
  params: params,
);

/// A number field wide enough for [answer], with room so the size of the
/// field does not give the answer away.
Map<String, dynamic> _numberFor(int answer, {String label = ''}) {
  var max = 9;
  while (max < answer * 2 + 9) {
    max = max * 10 + 9;
  }
  return _number(max, label: label);
}

int _popcount(int n) {
  var c = 0;
  for (var x = n; x > 0; x >>= 1) {
    c += x & 1;
  }
  return c;
}

int _choose(int n, int k) {
  if (k < 0 || k > n) return 0;
  var r = 1;
  for (var i = 1; i <= k; i++) {
    r = r * (n - k + i) ~/ i;
  }
  return r;
}

int _factorial(int n) => n <= 1 ? 1 : n * _factorial(n - 1);

List<int> _distinct(Rng r, int count, int lo, int hi) {
  final pool = [for (var v = lo; v <= hi; v++) v];
  r.shuffle(pool);
  return pool.sublist(0, count);
}

// --------------------------------------------------------------------- easy

Draft? _binary(Rng r, int step, int index) {
  final width = 4 + step;
  final n = r.range(3, (1 << width) - 1);
  if (_popcount(n) < 2 || n < (1 << (width - 1))) return null;
  if (index.isOdd) {
    return (
      archetype: 'pick',
      variant: 'to_binary',
      state: {
        'layout': 'bits',
        'tiles': [
          for (var i = width - 1; i >= 0; i--) {'v': 1 << i},
        ],
      },
      rules: {'rule': 'sum', 'target': n},
      params: {'n': n},
    );
  }
  return _answer('from_binary', [_bits(n, width)], [_number((1 << width) - 1)], [n]);
}

Draft? _bitwise(Rng r, int step, int index) {
  final width = [4, 6, 8][step];
  final a = r.range(1, (1 << width) - 1), b = r.range(1, (1 << width) - 1);
  if (index >= 8) {
    final s = r.range(1, 3);
    final left = index.isEven;
    final value = left ? a << s : a >> s;
    if (value == 0) return null;
    return _answer('shift', [_bits(a, width, label: 'a'), _expr(left ? 'a << $s' : 'a >> $s')], [_numberFor(value)], [
      value,
    ]);
  }
  final op = ['&', '|', '^'][index % 3];
  final value = switch (op) {
    '&' => a & b,
    '|' => a | b,
    _ => a ^ b,
  };
  if (value == 0 || a == b) return null;
  return _answer(
    'combine',
    [_bits(a, width, label: 'a'), _bits(b, width, label: 'b'), _expr('a $op b')],
    [_number((1 << width) - 1)],
    [value],
  );
}

Draft? _logic(Rng r, int step, int index) {
  final a = r.chance(0.5), b = r.chance(0.5), c = r.chance(0.5);
  final pool = <(String, bool)>[
    ...[
      ('A && B', a && b),
      ('A || B', a || b),
      ('!A', !a),
      ('A && !B', a && !b),
      ('!A || B', !a || b),
      ('!(A || B)', !(a || b)),
    ].take(step == 0 ? 6 : 0),
    if (step >= 1) ...[
      ('(A || B) && C', (a || b) && c),
      ('A && (B || C)', a && (b || c)),
      ('!(A && B)', !(a && b)),
      ('!A && !B', !a && !b),
      ('A || (B && !C)', a || (b && !c)),
      ('(A && B) || C', (a && b) || c),
    ],
    if (step == 2) ...[
      ('A != B', a != b),
      ('(A && B) || (!A && C)', (a && b) || (!a && c)),
      ('!(A || !B) && C', !(a || !b) && c),
      ('(A == B) || !C', (a == b) || !c),
    ],
  ];
  r.shuffle(pool);
  final picked = pool.take(3).toList();
  // A spread of true and false, so a row of the same answer never wins.
  final trues = picked.where((p) => p.$2).length;
  if (trues == 0 || trues == 3) return null;
  String show(bool v) => v ? 'true' : 'false';
  final values = step == 0 ? 'A = ${show(a)}    B = ${show(b)}' : 'A = ${show(a)}   B = ${show(b)}   C = ${show(c)}';
  return _answer(
    'evaluate',
    [_expr(values), for (var i = 0; i < 3; i++) _expr(picked[i].$1, label: '${i + 1}')],
    [for (var i = 0; i < 3; i++) _bool('${i + 1}')],
    [for (final p in picked) p.$2 ? 1 : 0],
  );
}

Draft? _logarithms(Rng r, int step, int index) {
  if (index % 3 == 0) {
    final n = r.range([9, 40, 200][step], [30, 200, 5000][step]);
    final halvings = (math.log(n) / math.ln2 - 1e-9).ceil();
    if (n & (n - 1) == 0) return null;
    return _answer('halvings', [], [_number(30)], [halvings], {'n': n});
  }
  switch (step) {
    case 0:
      final k = r.range(3, 8);
      return _answer('value', [_expr('log₂ ${1 << k}')], [_number(20)], [k]);
    case 1:
      final base = r.pick([3, 4, 5, 10]);
      final k = r.range(2, base == 10 ? 5 : 4);
      return _answer('value', [_expr('log${_sub(base)} ${math.pow(base, k).toInt()}')], [_number(20)], [k]);
    default:
      if (index.isEven) {
        final p = r.range(2, 6), q = r.range(2, 6);
        return _answer('value', [_expr('log₂ ${1 << p} + log₂ ${1 << q}')], [_number(30)], [p + q]);
      }
      final n = r.range(20, 1000);
      if (n & (n - 1) == 0) return null;
      final floor = (math.log(n) / math.ln2 + 1e-9).floor();
      return _answer('value', [_expr('⌊log₂ $n⌋')], [_number(20)], [floor]);
  }
}

String _sub(int n) => n.toString().split('').map((d) => '₀₁₂₃₄₅₆₇₈₉'[int.parse(d)]).join();

Draft? _counting(Rng r, int step, int index) {
  switch (step) {
    case 0:
      if (index.isOdd) {
        final n = r.range(3, 5);
        return _answer('line_up', [_expr('$n!')], [_numberFor(_factorial(n))], [_factorial(n)], {'n': n});
      }
      final a = r.range(3, 7), b = r.range(2, 6);
      return _answer('outfits', [], [_numberFor(a * b)], [a * b], {'a': a, 'b': b});
    case 1:
      final n = r.range(5, 9), k = r.range(2, 3);
      final ways = _factorial(n) ~/ _factorial(n - k);
      return _answer('podium', [_expr('P($n, $k)')], [_numberFor(ways)], [ways], {'n': n, 'k': k});
    default:
      final n = r.range(6, 12), k = r.range(2, 4);
      final ways = _choose(n, k);
      return _answer('team', [_expr('C($n, $k)')], [_numberFor(ways)], [ways], {'n': n, 'k': k});
  }
}

Draft? _modulo(Rng r, int step, int index) {
  switch (step) {
    case 0:
      final m = r.range(3, 9), a = r.range(m + 2, 60);
      if (a % m == 0) return null;
      return _answer('remainder', [_expr('$a mod $m')], [_number(9)], [a % m]);
    case 1:
      final h = r.range(1, 12), k = r.range(13, 100);
      return _answer('clock', [], [_number(12)], [(h - 1 + k) % 12 + 1], {'h': h, 'k': k});
    default:
      final base = r.pick([2, 3, 7, 8, 9]), k = r.range(10, 60);
      var last = 1;
      for (var i = 0; i < k; i++) {
        last = last * base % 10;
      }
      return _answer('last_digit', [_expr('$base^$k mod 10')], [_number(9)], [last], {'b': base, 'k': k});
  }
}

Draft? _binarySearch(Rng r, int step, int index) {
  final bisect = index >= 8;
  final hi = r.range([16, 40, 100][step], [32, 100, 250][step]);
  final mode = bisect ? 'bisect' : 'compare';
  final budget = ProbeArchetype.checksNeeded(hi, mode);
  return (
    archetype: 'probe',
    variant: mode,
    state: {'mode': mode, 'lo': 1, 'hi': hi, 'budget': budget},
    rules: const {},
    params: {'hi': hi, 'budget': budget},
  );
}

Draft? _twoPointers(Rng r, int step, int index) {
  final n = 6 + step;
  final values = _distinct(r, n, 1, 12 + step * 14)..sort();
  final i = r.nextInt(n - 1), j = i + 1 + r.nextInt(n - 1 - i);
  final target = values[i] + values[j];
  var pairs = 0;
  for (var x = 0; x < n; x++) {
    for (var y = x + 1; y < n; y++) {
      if (values[x] + values[y] == target) pairs++;
    }
  }
  if (pairs != 1 || j - i == n - 1) return null;
  return (
    archetype: 'pick',
    variant: 'pair_sum',
    state: {
      'layout': 'row',
      'tiles': [
        for (final v in values) {'v': v},
      ],
    },
    rules: {'rule': 'sum', 'target': target, 'count': 2},
    params: {'target': target},
  );
}

Draft? _stacks(Rng r, int step, int index) {
  final n = 4 + step;
  final items = [for (var i = 1; i <= n; i++) i];
  // Random pushes and pops always give an order a stack can make.
  final stack = <int>[], out = <int>[];
  var next = 0;
  while (out.length < n) {
    if (next < n && (stack.isEmpty || r.chance(0.5))) {
      stack.add(items[next++]);
    } else {
      out.add(stack.removeLast());
    }
  }
  final straight = List.generate(n, (i) => out[i] == items[i]).every((x) => x);
  final reversed = List.generate(n, (i) => out[i] == items[n - 1 - i]).every((x) => x);
  if (straight || (step > 0 && reversed)) return null;
  return (
    archetype: 'ops',
    variant: step == 2 ? 'stack_cap' : 'stack',
    state: {'mode': 'stack', 'items': items, 'target': out, if (step == 2) 'cap': 3},
    rules: const {},
    params: {if (step == 2) 'cap': 3},
  );
}

Draft? _queues(Rng r, int step, int index) {
  final start = [for (var i = 0; i < r.range(1, 3); i++) r.range(1, 9)];
  final queue = [...start];
  final ops = <String>[];
  final removed = <int>[];
  final count = [5, 7, 9][step];
  for (var i = 0; i < count; i++) {
    if (queue.isNotEmpty && r.chance(0.45)) {
      removed.add(queue.removeAt(0));
      ops.add('←');
    } else {
      final v = r.range(1, 9);
      queue.add(v);
      ops.add('→$v');
    }
  }
  if (queue.isEmpty || removed.isEmpty) return null;
  final board = [_cells(start, label: 'queue'), _expr(ops.join('  '))];
  if (step == 0) return _answer('front', board, [_number(9)], [queue.first]);
  if (step == 1) {
    return _answer(
      'front_size',
      board,
      [_number(9, label: '@field.front'), _number(12, label: '@field.size')],
      [queue.first, queue.length],
    );
  }
  return _answer(
    'front_last',
    board,
    [_number(9, label: '@field.front'), _number(9, label: '@field.last_out')],
    [queue.first, removed.last],
  );
}

// ------------------------------------------------------------------- medium

Draft? _bitTricks(Rng r, int step, int index) {
  switch (index % 3) {
    case 0:
      final n = r.range([20, 60, 120][step], [63, 200, 1000][step]);
      return _answer('popcount', [_expr('n = $n')], [_number(12)], [_popcount(n)], {'n': n});
    case 1:
      final n = r.range([12, 40, 100][step], [63, 255, 999][step]);
      if (_popcount(n) < 2) return null;
      return _answer('clear_low', [_expr('n = $n'), _expr('n & (n − 1)')], [_numberFor(n)], [n & (n - 1)]);
    default:
      final values = <int>[];
      while (values.length < 3) {
        final v = r.chance(0.5) ? 1 << r.range(3, 4 + step * 3) : r.range(10, 40 << step);
        if (!values.contains(v)) values.add(v);
      }
      final answers = [for (final v in values) v & (v - 1) == 0 ? 1 : 0];
      if (answers.every((a) => a == answers.first)) return null;
      return _answer('power_of_two', [], [for (final v in values) _bool('$v')], answers);
  }
}

Draft? _sorting(Rng r, int step, int index) {
  final adjacent = index.isOdd;
  final n = (adjacent ? 4 : 5) + step;
  final items = _distinct(r, n, 1, 30);
  final budget = OpsArchetype.fewestSwaps(items, adjacent: adjacent);
  if (budget < 2 + step) return null;
  return (
    archetype: 'ops',
    variant: adjacent ? 'bubble' : 'any_swap',
    state: {'mode': 'swap', 'items': items, 'adjacent': adjacent, 'budget': budget},
    rules: const {},
    params: {'budget': budget},
  );
}

Draft? _hashing(Rng r, int step, int index) {
  final m = r.range(7, 11);
  final keys = _distinct(r, 4 + step, 10, 99);
  final hash = _expr('h(k) = k mod $m');
  switch (index % 3) {
    case 0:
      return _answer(
        'bucket',
        [_cells(keys, label: 'keys'), hash],
        [_number(m - 1, label: 'h(${keys[0]})'), _number(m - 1, label: 'h(${keys[1]})')],
        [keys[0] % m, keys[1] % m],
      );
    case 1:
      final used = <int>{};
      var hits = 0;
      for (final k in keys) {
        if (!used.add(k % m)) hits++;
      }
      if (hits == 0) return null;
      return _answer('collisions', [_cells(keys, label: 'keys'), hash], [_number(keys.length)], [hits]);
    default:
      final table = List<int?>.filled(m, null);
      var last = 0;
      var moved = false;
      for (final k in keys) {
        var slot = k % m;
        while (table[slot] != null) {
          slot = (slot + 1) % m;
          moved = true;
        }
        table[slot] = k;
        last = slot;
      }
      if (!moved) return null;
      return _answer('probing', [_cells(keys, label: 'keys'), hash], [_number(m - 1)], [last], {'last': keys.last});
  }
}

Draft? _recursion(Rng r, int step, int index) {
  if (index % 3 == 0) {
    final n = r.range(4 + step, 6 + step);
    final calls = List<int>.filled(n + 1, 1);
    for (var i = 2; i <= n; i++) {
      calls[i] = 1 + calls[i - 1] + calls[i - 2];
    }
    return _answer(
      'calls',
      [_expr('fib(n) = fib(n − 1) + fib(n − 2)'), _expr('fib(0), fib(1): no more calls')],
      [_numberFor(calls[n])],
      [calls[n]],
      {'n': n},
    );
  }
  final kinds = [
    ('f(0) = 0', 'f(n) = f(n − 1) + n', (int n) => n * (n + 1) ~/ 2),
    ('f(0) = 1', 'f(n) = 2 · f(n − 1)', (int n) => 1 << n),
    ('f(0) = 1', 'f(n) = 2 · f(n − 1) + 1', (int n) => (1 << (n + 1)) - 1),
    ('f(0) = 0, f(1) = 1', 'f(n) = f(n − 1) + f(n − 2)', _fib),
    ('f(0) = 2', 'f(n) = 3 · f(n − 1) − 1', (int n) => (math.pow(3, n).toInt() + 3) ~/ 2),
  ];
  final kind = kinds[r.nextInt(step == 0 ? 3 : kinds.length)];
  final n = r.range(3 + step, 5 + step * 2);
  final value = kind.$3(n);
  if (value > 9999) return null;
  return _answer('value', [_expr(kind.$1), _expr(kind.$2), _expr('f($n) = ?')], [_numberFor(value)], [value]);
}

int _fib(int n) => n < 2 ? n : _fib(n - 1) + _fib(n - 2);

Draft? _slidingWindow(Rng r, int step, int index) {
  final n = 7 + step;
  final k = 2 + step;
  final values = [for (var i = 0; i < n; i++) r.range(1, 9)];
  var best = 0, ties = 0;
  for (var i = 0; i + k <= n; i++) {
    final s = values.sublist(i, i + k).fold(0, (a, b) => a + b);
    if (s > best) {
      best = s;
      ties = 1;
    } else if (s == best) {
      ties++;
    }
  }
  if (ties > 1) return null;
  return (
    archetype: 'pick',
    variant: 'window',
    state: {
      'layout': 'row',
      'tiles': [
        for (final v in values) {'v': v},
      ],
    },
    rules: {'rule': 'window', 'k': k, 'best': best},
    params: {'k': k},
  );
}

Draft? _prefixSums(Rng r, int step, int index) {
  final n = 6 + step;
  final a = [for (var i = 0; i < n; i++) r.range(1, 9 + step * 5)];
  final i = r.nextInt(n - 2), j = i + 2 + r.nextInt(n - i - 2);
  final sum = a.sublist(i, j + 1).fold(0, (x, y) => x + y);
  final range = _expr('a[$i] + … + a[$j]');
  if (step == 0 || index.isOdd) {
    return _answer('range', [_cells(a, label: 'a', index: true), range], [_numberFor(sum)], [sum]);
  }
  final prefix = <int>[];
  var run = 0;
  for (final v in a) {
    run += v;
    prefix.add(run);
  }
  return _answer('from_prefix', [_cells(prefix, label: 'P', index: true), range], [_numberFor(sum)], [sum]);
}

Draft? _greedy(Rng r, int step, int index) {
  final n = 5 + step;
  final tiles = <Map<String, int>>[];
  for (var i = 0; i < n; i++) {
    final s = r.range(0, 10), len = r.range(1, 4);
    tiles.add({'v': 1, 's': s, 'e': math.min(12, s + len)});
  }
  final probe = LevelSpec(
    id: 'probe',
    archetypeId: 'pick',
    place: 0,
    index: 0,
    difficulty: 1,
    initialState: {'layout': 'bars', 'tiles': tiles},
    validationRules: {'rule': 'intervals', 'best': 0},
    hints: const ['-'],
    i18nKey: '-',
    conceptId: '-',
  );
  final best = PickArchetype.bestPossible(PickScene(probe));
  if (best < 2 || best >= n - 1) return null;
  return (
    archetype: 'pick',
    variant: 'meetings',
    state: {'layout': 'bars', 'tiles': tiles},
    rules: {'rule': 'intervals', 'best': best},
    params: const {},
  );
}

Draft? _heaps(Rng r, int step, int index) {
  final heap = <int>[];
  final ops = <String>[];
  final out = <int>[];
  final count = [6, 8, 10][step];
  for (var i = 0; i < count; i++) {
    if (heap.length >= 2 && r.chance(0.4)) {
      heap.sort();
      out.add(heap.removeAt(0));
      ops.add('−');
    } else {
      final v = r.range(1, 30);
      if (heap.contains(v)) continue;
      heap.add(v);
      ops.add('+$v');
    }
  }
  if (out.isEmpty || heap.isEmpty) return null;
  heap.sort();
  final board = [_expr(ops.join('  '))];
  if (step == 0) return _answer('last_out', board, [_number(30)], [out.last]);
  if (step == 1) {
    return _answer(
      'first_last',
      board,
      [_number(30, label: '@field.first_out'), _number(30, label: '@field.last_out')],
      [out.first, out.last],
    );
  }
  if (out.length < 2) return null;
  return _answer(
    'top_size',
    board,
    [_number(30, label: '@field.top'), _number(12, label: '@field.size')],
    [heap.first, heap.length],
  );
}

Map<String, dynamic> _grid(int cols, int rows, List<int> cells, int start, int goal) => {
  'cols': cols,
  'rows': rows,
  'cells': cells,
  'start': [start % cols, start ~/ cols],
  'goal': [goal % cols, goal ~/ cols],
};

Draft? _bfs(Rng r, int step, int index) {
  final size = 5 + step;
  final cells = [for (var i = 0; i < size * size; i++) r.chance(0.28) ? -1 : 1];
  final start = r.nextInt(size), goal = size * size - 1 - r.nextInt(size);
  cells[start] = 1;
  cells[goal] = 1;
  final probe = RouteScene(_routeProbe(_grid(size, size, cells, start, goal)));
  final path = RouteArchetype.cheapest(probe);
  if (path == null) return null;
  final best = path.length - 1;
  final straight = (start % size - goal % size).abs() + (start ~/ size - goal ~/ size).abs();
  if (best < straight + (step == 0 ? 0 : 2)) return null;
  return (
    archetype: 'route',
    variant: 'fewest_steps',
    state: _grid(size, size, cells, start, goal),
    rules: {'best': best},
    params: const {},
  );
}

LevelSpec _routeProbe(Map<String, dynamic> state) => LevelSpec(
  id: 'probe',
  archetypeId: 'route',
  place: 0,
  index: 0,
  difficulty: 1,
  initialState: state,
  validationRules: const {'best': 0},
  hints: const ['-'],
  i18nKey: '-',
  conceptId: '-',
);

Draft? _combinatorics(Rng r, int step, int index) {
  switch (index % 4) {
    case 0:
      final n = r.range(8, 12), k = r.range(3, 5);
      return _answer('choose', [_expr('C($n, $k)')], [_numberFor(_choose(n, k))], [_choose(n, k)]);
    case 1:
      final k = r.range(4, 6 + step * 2), n = r.range(2, 4);
      final ways = _choose(k + n - 1, n - 1);
      return _answer('sweets', [], [_numberFor(ways)], [ways], {'k': k, 'n': n});
    case 2:
      final c = r.range(3, 6), m = r.range(2, 2 + step);
      final need = c * (m - 1) + 1;
      return _answer('socks', [], [_numberFor(need)], [need], {'c': c, 'm': m});
    default:
      final n = r.range(30, 60 + step * 40), a = r.range(2, 5), b = r.range(a + 1, 7);
      if (b % a == 0) return null;
      final lcm = a * b ~/ _gcd(a, b);
      final count = n ~/ a + n ~/ b - n ~/ lcm;
      return _answer('divisible', [], [_numberFor(count)], [count], {'n': n, 'a': a, 'b': b});
  }
}

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

// --------------------------------------------------------------------- hard

Draft? _dynamicProgramming(Rng r, int step, int index) {
  switch (index % 3) {
    case 0:
      final three = step > 0 && r.chance(0.5);
      final n = three ? r.range(6, 10) : r.range(8, 14);
      final ways = List<int>.filled(n + 1, 0)..[0] = 1;
      for (var i = 1; i <= n; i++) {
        ways[i] = ways[i - 1] + (i >= 2 ? ways[i - 2] : 0) + (three && i >= 3 ? ways[i - 3] : 0);
      }
      return _answer('stairs', [_expr(three ? '1, 2 or 3' : '1 or 2')], [_numberFor(ways[n])], [ways[n]], {'n': n});
    case 1:
      final coins = r.pick([
        [1, 3, 4],
        [1, 5, 6],
        [1, 4, 6],
        [1, 7, 10],
      ]);
      final amount = r.range(8, 20 + step * 10);
      final best = List<int>.filled(amount + 1, 1 << 20)..[0] = 0;
      for (var v = 1; v <= amount; v++) {
        for (final c in coins) {
          if (c <= v && best[v - c] + 1 < best[v]) best[v] = best[v - c] + 1;
        }
      }
      // Only worth asking when taking the biggest coin first goes wrong.
      var greedy = 0, left = amount;
      for (final c in coins.reversed) {
        greedy += left ~/ c;
        left %= c;
      }
      if (greedy == best[amount]) return null;
      return _answer('coins', [_cells(coins, label: 'coins')], [_number(30)], [best[amount]], {'amount': amount});
    default:
      final size = 4 + step;
      final blocked = <int>{};
      for (var i = 0; i < size; i++) {
        final cell = r.nextInt(size * size);
        if (cell != 0 && cell != size * size - 1) blocked.add(cell);
      }
      final paths = List<int>.filled(size * size, 0);
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final i = y * size + x;
          if (blocked.contains(i)) continue;
          paths[i] = i == 0 ? 1 : (x > 0 ? paths[i - 1] : 0) + (y > 0 ? paths[i - size] : 0);
        }
      }
      final total = paths.last;
      if (total < 3) return null;
      return _answer(
        'grid_paths',
        [
          for (var y = 0; y < size; y++)
            _cells([for (var x = 0; x < size; x++) blocked.contains(y * size + x) ? '■' : '·']),
        ],
        [_numberFor(total)],
        [total],
      );
  }
}

Draft? _knapsack(Rng r, int step, int index) {
  final n = 5 + step;
  final tiles = [
    for (var i = 0; i < n; i++) {'v': r.range(2, 15), 'w': r.range(1, 8)},
  ];
  final totalW = tiles.fold(0, (a, t) => a + t['w']!);
  final cap = (totalW * (0.4 + r.nextDouble() * 0.2)).round();
  final probe = LevelSpec(
    id: 'probe',
    archetypeId: 'pick',
    place: 0,
    index: 0,
    difficulty: 1,
    initialState: {'layout': 'items', 'tiles': tiles},
    validationRules: {'rule': 'knapsack', 'cap': cap, 'best': 0},
    hints: const ['-'],
    i18nKey: '-',
    conceptId: '-',
  );
  final best = PickArchetype.bestPossible(PickScene(probe));
  // Greedy by value per weight should fall short, so the puzzle needs real thought.
  final order = [for (var i = 0; i < n; i++) i]
    ..sort((a, b) => (tiles[b]['v']! * tiles[a]['w']!).compareTo(tiles[a]['v']! * tiles[b]['w']!));
  var w = 0, v = 0;
  for (final i in order) {
    if (w + tiles[i]['w']! <= cap) {
      w += tiles[i]['w']!;
      v += tiles[i]['v']!;
    }
  }
  if (step > 0 && v == best) return null;
  return (
    archetype: 'pick',
    variant: 'bag',
    state: {'layout': 'items', 'tiles': tiles},
    rules: {'rule': 'knapsack', 'cap': cap, 'best': best},
    params: {'cap': cap},
  );
}

Draft? _shortestPaths(Rng r, int step, int index) {
  final size = 5 + (step == 2 ? 1 : 0);
  final cells = [for (var i = 0; i < size * size; i++) r.chance(0.12) ? -1 : r.range(1, 9)];
  const start = 0;
  final goal = size * size - 1;
  cells[start] = 1;
  cells[goal] = r.range(1, 9);
  final probe = RouteScene(_routeProbe(_grid(size, size, cells, start, goal)));
  final path = RouteArchetype.cheapest(probe);
  if (path == null) return null;
  final best = path.skip(1).fold(0, (a, c) => a + cells[c]);
  // The cheapest path should not be one of the shortest ones in steps.
  if (step > 0 && path.length - 1 == 2 * (size - 1)) return null;
  return (
    archetype: 'route',
    variant: 'cheapest',
    state: _grid(size, size, cells, start, goal),
    rules: {'best': best},
    params: const {},
  );
}

Draft? _topologicalSort(Rng r, int step, int index) {
  final n = 5 + step + (index > 6 ? 1 : 0);
  final order = [for (var i = 0; i < n; i++) i];
  r.shuffle(order);
  final deps = <List<int>>[];
  for (var a = 0; a < n; a++) {
    for (var b = a + 1; b < n; b++) {
      if (r.chance(0.32)) deps.add([order[a], order[b]]);
    }
  }
  if (deps.length < n - 1) return null;
  return (
    archetype: 'ops',
    variant: 'tasks',
    state: {
      'mode': 'order',
      'items': [for (var i = 0; i < n; i++) i],
      'labels': [for (var i = 0; i < n; i++) String.fromCharCode(65 + i)],
      'deps': deps,
    },
    rules: const {},
    params: const {},
  );
}

Draft? _searchTheAnswer(Rng r, int step, int index) {
  if (index % 3 == 0) {
    final n = r.range([50, 400, 2000][step], [400, 2000, 9999][step]);
    final root = math.sqrt(n).floor();
    if (root * root == n) return null;
    return _answer('isqrt', [], [_number(99)], [root], {'n': n});
  }
  final count = 5 + step;
  final weights = [for (var i = 0; i < count; i++) r.range(1, 12)];
  final days = r.range(2, 3 + step);
  bool fits(int cap) {
    var used = 1, load = 0;
    for (final w in weights) {
      if (w > cap) return false;
      if (load + w > cap) {
        used++;
        load = 0;
      }
      load += w;
    }
    return used <= days;
  }

  var cap = weights.reduce(math.max);
  while (!fits(cap)) {
    cap++;
  }
  if (cap == weights.reduce(math.max)) return null;
  return _answer('ship', [_cells(weights, label: 'kg')], [_number(99)], [cap], {'days': days});
}

Draft? _xorTricks(Rng r, int step, int index) {
  if (index.isOdd) {
    final n = 5 + step;
    final values = _distinct(r, n, 1, 31);
    var target = 0;
    var size = 0;
    for (final v in values) {
      if (r.chance(0.5)) {
        target ^= v;
        size++;
      }
    }
    if (size < 2 || target == 0 || values.contains(target)) return null;
    return (
      archetype: 'pick',
      variant: 'subset',
      state: {
        'layout': 'row',
        'tiles': [
          for (final v in values) {'v': v},
        ],
      },
      rules: {'rule': 'xor', 'target': target},
      params: {'target': target},
    );
  }
  if (index == 10) {
    final a = r.range(3, 15), b = r.range(3, 15);
    if (a == b) return null;
    return _answer(
      'swap',
      [_expr('a = $a,  b = $b'), _expr('a ^= b;  b ^= a;  a ^= b')],
      [_number(15, label: 'a'), _number(15, label: 'b')],
      [b, a],
    );
  }
  final pairs = _distinct(r, 3 + step, 1, 40);
  final single = pairs.removeLast();
  final row = [...pairs, ...pairs, single];
  r.shuffle(row);
  return _answer('single', [_cells(row)], [_number(40)], [single]);
}

Draft? _unionFind(Rng r, int step, int index) {
  final n = 6 + step * 2;
  final parent = [for (var i = 0; i <= n; i++) i];
  int find(int x) => parent[x] == x ? x : parent[x] = find(parent[x]);
  final links = <String>[];
  final count = n - 2 - r.nextInt(2);
  for (var i = 0; i < count; i++) {
    final a = r.range(1, n), b = r.range(1, n);
    if (a == b) continue;
    links.add('$a–$b');
    parent[find(a)] = find(b);
  }
  final sizes = <int, int>{};
  for (var i = 1; i <= n; i++) {
    sizes.update(find(i), (v) => v + 1, ifAbsent: () => 1);
  }
  if (sizes.length < 2) return null;
  final board = [_expr('1 … $n'), _expr(links.join('   '))];
  if (step < 2) return _answer('groups', board, [_number(n)], [sizes.length], {'n': n});
  return _answer(
    'groups_biggest',
    board,
    [_number(n, label: '@field.groups'), _number(n, label: '@field.biggest')],
    [sizes.length, sizes.values.reduce(math.max)],
    {'n': n},
  );
}

Draft? _probability(Rng r, int step, int index) {
  switch (index % 3) {
    case 0:
      final s = r.range(3, 11);
      final ways = 6 - (s - 7).abs();
      return _answer('dice_sum', [], [_number(36)], [ways], {'s': s});
    case 1:
      final n = r.range(4, 6 + step), k = r.range(1, n - 1);
      return _answer('heads', [_expr('2^$n outcomes')], [_numberFor(_choose(n, k))], [_choose(n, k)], {'n': n, 'k': k});
    default:
      final n = r.range(2, 4);
      final ways = math.pow(6, n).toInt() - math.pow(5, n).toInt();
      return _answer('at_least_one_six', [_expr('6^$n outcomes')], [_numberFor(ways)], [ways], {'n': n});
  }
}

Draft? _caching(Rng r, int step, int index) {
  final cap = 2 + step;
  final letters = 'ABCDEF'.substring(0, cap + 2).split('');
  final requests = [for (var i = 0; i < 8 + step * 2; i++) r.pick(letters)];
  final lru = index.isOdd;
  final cache = <String>[];
  var misses = 0;
  for (final q in requests) {
    if (cache.contains(q)) {
      if (lru) {
        cache
          ..remove(q)
          ..add(q);
      }
      continue;
    }
    misses++;
    if (cache.length == cap) cache.removeAt(0);
    cache.add(q);
  }
  if (misses == requests.toSet().length) return null; // no evictions mattered
  return _answer(lru ? 'lru' : 'fifo', [_cells(requests)], [_number(requests.length)], [misses], {'cap': cap});
}

Draft? _rateLimiting(Rng r, int step, int index) {
  if (index % 3 == 0) {
    final m = r.range(4, 9), n = r.range(20, 200);
    return _answer('round_robin', [], [_number(m)], [(n - 1) % m + 1], {'m': m, 'n': n});
  }
  if (step == 2 && index.isEven) {
    final servers = 3;
    final jobs = [for (var i = 0; i < 7; i++) r.range(1, 9)];
    final load = List<int>.filled(servers, 0);
    for (final j in jobs) {
      var low = 0;
      for (var s = 1; s < servers; s++) {
        if (load[s] < load[low]) low = s;
      }
      load[low] += j;
    }
    return _answer(
      'least_loaded',
      [_cells(jobs, label: 'jobs')],
      [_number(60)],
      [load.reduce(math.max)],
      {'servers': servers},
    );
  }
  final cap = r.range(2, 4), rate = 1;
  final perSecond = [for (var i = 0; i < 5 + step; i++) r.range(0, 4)];
  var tokens = cap, allowed = 0;
  for (var t = 0; t < perSecond.length; t++) {
    if (t > 0) tokens = math.min(cap, tokens + rate);
    final ok = math.min(tokens, perSecond[t]);
    allowed += ok;
    tokens -= ok;
  }
  final total = perSecond.fold(0, (a, b) => a + b);
  if (allowed == total || allowed == 0) return null;
  return _answer(
    'token_bucket',
    [_cells(perSecond, label: 's', index: true)],
    [_number(total)],
    [allowed],
    {'cap': cap, 'rate': rate},
  );
}
