import '../level_spec.dart';
import '../scene.dart';

class CargoPiece {
  CargoPiece(this.w, this.h, {required this.heavy, this.col, this.row, this.rotated = false})
    : _col = col,
      _row = row,
      _rotated = rotated;
  final int w;
  final int h;
  final bool heavy;
  final int? _col;
  final int? _row;
  final bool _rotated;

  /// Top-left cell while loaded, null while on the dock.
  int? col;
  int? row;
  bool rotated;

  bool get loaded => col != null;
  int get width => rotated ? h : w;
  int get height => rotated ? w : h;
  int get weight => w * h * (heavy ? 3 : 1);

  void _reset() {
    col = _col;
    row = _row;
    rotated = _rotated;
  }
}

/// Crates loaded into a ship's hold. Every crate must go aboard, and on
/// some ships the weight must sit evenly across the middle.
class CargoScene extends Scene {
  CargoScene(super.level) {
    final s = JsonReader(level.initialState, level.id, 'initialState.');
    final rules = JsonReader(level.validationRules, level.id, 'validationRules.');
    final hold = s.object('hold');
    cols = hold.integer('cols');
    rows = hold.integer('rows');
    if (cols < 1 || rows < 1 || cols > 10 || rows > 8) {
      throw LevelFormatException('hold must be 1-10 wide and 1-8 deep', levelId: level.id);
    }
    for (final cell in hold.list('blocked', optional: true)) {
      if (cell is! List || cell.length != 2 || cell.any((e) => e is! int)) {
        throw LevelFormatException('blocked cells must be [col, row]', levelId: level.id);
      }
      final c = cell[0] as int, r = cell[1] as int;
      if (c < 0 || c >= cols || r < 0 || r >= rows) {
        throw LevelFormatException('blocked cell outside the hold', levelId: level.id);
      }
      blocked.add(r * cols + c);
    }
    for (final p in s.objects('pieces')) {
      pieces.add(
        CargoPiece(
          p.integer('w'),
          p.integer('h'),
          heavy: p.boolean('heavy', orElse: false),
          col: p.integerOrNull('col'),
          row: p.integerOrNull('row'),
          rotated: p.boolean('rotated', orElse: false),
        ),
      );
    }
    requireAll = rules.boolean('requireAllLoaded', orElse: true);
    balanceTolerance = rules.numberOrNull('balanceTolerance');
    if (pieces.isEmpty || pieces.any((p) => p.w < 1 || p.h < 1)) {
      throw LevelFormatException('needs crates with positive sizes', levelId: level.id);
    }
    // Starting positions must be legal.
    final start = [for (final p in pieces) (p.col, p.row, p.rotated)];
    for (final p in pieces) {
      p.col = null;
      p.row = null;
    }
    for (var i = 0; i < pieces.length; i++) {
      final (c, r, rot) = start[i];
      if (c == null && r == null) continue;
      if (c == null || r == null || !place(i, c, r, rotated: rot)) {
        throw LevelFormatException('a crate starts in an invalid spot', levelId: level.id);
      }
    }
  }

  late final int cols;
  late final int rows;
  final Set<int> blocked = {};
  final List<CargoPiece> pieces = [];
  late final bool requireAll;
  late final double? balanceTolerance;

  /// Index of the crate covering a cell, or null.
  int? pieceAt(int col, int row) {
    for (var i = 0; i < pieces.length; i++) {
      final p = pieces[i];
      final pc = p.col, pr = p.row;
      if (pc == null || pr == null) continue;
      if (col >= pc && col < pc + p.width && row >= pr && row < pr + p.height) return i;
    }
    return null;
  }

  bool canPlace(int piece, int col, int row, {required bool rotated}) {
    final p = pieces[piece];
    final w = rotated ? p.h : p.w;
    final h = rotated ? p.w : p.h;
    if (col < 0 || row < 0 || col + w > cols || row + h > rows) return false;
    for (var r = row; r < row + h; r++) {
      for (var c = col; c < col + w; c++) {
        if (blocked.contains(r * cols + c)) return false;
        final other = pieceAt(c, r);
        if (other != null && other != piece) return false;
      }
    }
    return true;
  }

  bool place(int piece, int col, int row, {required bool rotated}) {
    if (!canPlace(piece, col, row, rotated: rotated)) return false;
    final p = pieces[piece];
    p.col = col;
    p.row = row;
    p.rotated = rotated;
    return true;
  }

  /// Takes a crate back to the dock.
  void unload(int piece) {
    pieces[piece].col = null;
    pieces[piece].row = null;
  }

  int get unloaded => pieces.where((p) => !p.loaded).length;

  /// Net sideways pull of the loaded weight about the middle of the hold.
  /// Positive means the right side is heavier.
  double get moment {
    var m = 0.0;
    for (final p in pieces) {
      final c = p.col;
      if (c != null) m += p.weight * (c + p.width / 2 - cols / 2);
    }
    return m;
  }

  @override
  void reset() {
    for (final p in pieces) {
      p._reset();
    }
  }

  @override
  Map<String, dynamic> snapshot() => {
    'pieces': [
      for (final p in pieces) p.loaded ? [p.col, p.row, p.rotated ? 1 : 0] : null,
    ],
  };

  @override
  void restore(Map<String, dynamic> snapshot) {
    final list = snapshot['pieces'] as List;
    if (list.length != pieces.length) throw ArgumentError('snapshot does not fit this level');
    for (final p in pieces) {
      p.col = null;
      p.row = null;
    }
    for (var i = 0; i < pieces.length; i++) {
      final e = list[i];
      if (e == null) continue;
      final v = (e as List).cast<int>();
      if (!place(i, v[0], v[1], rotated: v[2] == 1)) throw ArgumentError('snapshot overlaps or leaves the hold');
    }
  }

  @override
  Outcome evaluate() {
    final m = moment;
    final detail = {'moment': m};
    if (requireAll && unloaded > 0) {
      return Outcome.failed('left_behind', magnitude: unloaded.toDouble(), detail: detail);
    }
    final tol = balanceTolerance;
    if (tol != null && m.abs() > tol + 1e-9) {
      return Outcome.failed(m < 0 ? 'lists_left' : 'lists_right', magnitude: m, detail: detail);
    }
    return Outcome.solved(detail);
  }

  @override
  SimResult simulate() {
    final outcome = evaluate();
    final b = TimelineBuilder(120);
    if (outcome.success) {
      b.spring('list', target: 0, velocity: 0.25, omega: 6, damping: 0.3);
      b.ramp('sail', 40, 115);
    } else if (outcome.kind == 'left_behind') {
      b.fill('list', (_) => 0);
      b.spring('shake', target: 0, velocity: 7, omega: 30, damping: 0.14);
      b.fill('sail', (_) => 0);
    } else {
      final m = moment;
      final rest = m.sign * (0.05 + 0.012 * m.abs()).clamp(0.0, 0.28);
      b.spring('list', target: rest, omega: 5, damping: 0.2);
      b.fill('sail', (_) => 0);
    }
    return SimResult(outcome, b.build());
  }
}

class CargoArchetype extends Archetype {
  const CargoArchetype();

  @override
  String get id => 'cargo_packing';

  @override
  CargoScene create(LevelSpec level) => CargoScene(level);

  /// Visits every way of loading all crates. [visit] returns false to stop.
  void _enumerate(CargoScene scene, bool Function() visit, {int limit = 200000}) {
    for (var i = 0; i < scene.pieces.length; i++) {
      scene.unload(i);
    }
    final free = scene.cols * scene.rows - scene.blocked.length;
    final area = scene.pieces.fold<int>(0, (a, p) => a + p.w * p.h);
    if (area > free) return;
    final skipped = <int>{};
    var spare = free - area;
    var visits = 0;
    var stop = false;

    void go() {
      if (stop) return;
      if (scene.unloaded == 0) {
        visits++;
        if (!visit() || visits >= limit) stop = true;
        return;
      }
      // First cell that is still open, reading row by row.
      var cell = -1;
      for (var i = 0; i < scene.cols * scene.rows; i++) {
        if (scene.blocked.contains(i) || skipped.contains(i)) continue;
        if (scene.pieceAt(i % scene.cols, i ~/ scene.cols) == null) {
          cell = i;
          break;
        }
      }
      if (cell < 0) return;
      final c = cell % scene.cols, r = cell ~/ scene.cols;
      final tried = <String>{};
      for (var i = 0; i < scene.pieces.length; i++) {
        final p = scene.pieces[i];
        if (p.loaded) continue;
        for (final rot in p.w == p.h ? const [false] : const [false, true]) {
          final key = '${rot ? p.h : p.w}x${rot ? p.w : p.h}${p.heavy ? 'h' : ''}';
          if (!tried.add(key)) continue;
          if (scene.place(i, c, r, rotated: rot)) {
            go();
            scene.unload(i);
            if (stop) return;
          }
        }
      }
      if (spare > 0) {
        spare--;
        skipped.add(cell);
        go();
        skipped.remove(cell);
        spare++;
      }
    }

    go();
  }

  @override
  Solution? solve(LevelSpec level) {
    final scene = create(level);
    Map<String, dynamic>? found;
    _enumerate(scene, () {
      if (scene.evaluate().success) {
        found = scene.snapshot();
        return false;
      }
      return true;
    });
    return found == null ? null : Solution(found!, effort: scene.pieces.length);
  }

  @override
  double? winFraction(LevelSpec level) {
    final scene = create(level);
    if (scene.balanceTolerance == null) return null;
    var total = 0;
    var wins = 0;
    _enumerate(scene, () {
      total++;
      if (scene.evaluate().success) wins++;
      return true;
    }, limit: 20000);
    return total == 0 ? 0 : wins / total;
  }
}
