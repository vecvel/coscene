import '../level_spec.dart';
import '../scene.dart';

/// One row of what the player reads before answering: an expression, a row
/// of bits, or a row of cells such as an array, a stack or a queue.
class BoardRow {
  const BoardRow(this.kind, this.cells, {this.label = '', this.mark = const [], this.index = false});

  factory BoardRow.fromJson(JsonReader r) {
    final kind = r.string('kind');
    if (!const {'expr', 'bits', 'cells', 'stack'}.contains(kind)) {
      throw LevelFormatException('board row kind "$kind" is not known', levelId: r.levelId);
    }
    final cells = kind == 'expr' ? [r.string('text')] : r.strings('cells');
    return BoardRow(
      kind,
      cells,
      label: r.string('label', orElse: ''),
      mark: r.integers('mark', optional: true),
      index: r.boolean('index', orElse: false),
    );
  }

  /// `expr`, `bits`, `cells` or `stack`.
  final String kind;
  final List<String> cells;
  final String label;

  /// Indexes of cells drawn highlighted.
  final List<int> mark;

  /// Whether each cell shows its index (0, 1, 2...) underneath.
  final bool index;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    if (kind == 'expr') 'text': cells.first else 'cells': cells,
    if (label.isNotEmpty) 'label': label,
    if (mark.isNotEmpty) 'mark': mark,
    if (index) 'index': true,
  };
}

/// One value the player fills in.
class AnswerField {
  AnswerField(this.mode, {this.max = 1, this.options = const [], this.label = ''});

  factory AnswerField.fromJson(JsonReader r) {
    final mode = r.string('mode');
    final label = r.string('label', orElse: '');
    return switch (mode) {
      'number' => AnswerField(mode, max: r.integer('max'), label: label),
      'bool' => AnswerField(mode, max: 1, label: label),
      'choice' => AnswerField(mode, options: r.strings('options'), max: r.strings('options').length - 1, label: label),
      _ => throw LevelFormatException('answer mode "$mode" is not known', levelId: r.levelId),
    };
  }

  /// `number` (0 to [max]), `bool` (0 false, 1 true) or `choice` (an index
  /// into [options]).
  final String mode;
  final int max;
  final List<String> options;

  /// Shown next to the field. Text starting with @ is a dictionary key.
  final String label;

  int get space => max + 1;

  int? value;

  bool accepts(int v) => v >= 0 && v <= max;
}

/// Work something out and enter the result: the value of an expression, the
/// state after some operations, a count.
class AnswerScene extends Scene {
  AnswerScene(super.level) {
    final s = JsonReader(level.initialState, level.id, 'initialState.');
    board.addAll(s.objects('board').map(BoardRow.fromJson));
    fields.addAll(s.objects('fields').map(AnswerField.fromJson));
    final r = JsonReader(level.validationRules, level.id, 'validationRules.');
    answers.addAll(r.integers('answers'));
    if (fields.isEmpty || fields.length > 4 || answers.length != fields.length) {
      throw LevelFormatException('needs 1 to 4 fields and one answer per field', levelId: level.id);
    }
    for (var i = 0; i < fields.length; i++) {
      if (!fields[i].accepts(answers[i])) {
        throw LevelFormatException('answer ${i + 1} is outside its field', levelId: level.id);
      }
      if (fields[i].mode == 'choice' && fields[i].options.length < 2) {
        throw LevelFormatException('a choice needs at least two options', levelId: level.id);
      }
    }
  }

  final List<BoardRow> board = [];
  final List<AnswerField> fields = [];
  final List<int> answers = [];

  @override
  void reset() {
    for (final f in fields) {
      f.value = null;
    }
  }

  @override
  Map<String, dynamic> snapshot() => {
    'values': [for (final f in fields) f.value],
  };

  @override
  void restore(Map<String, dynamic> snapshot) {
    final values = snapshot['values'] as List;
    if (values.length != fields.length) throw ArgumentError('snapshot does not fit this level');
    for (var i = 0; i < fields.length; i++) {
      final v = values[i];
      if (v != null && (v is! int || !fields[i].accepts(v))) throw ArgumentError('snapshot value out of range');
      fields[i].value = v as int?;
    }
  }

  /// Which fields hold the right value, in order.
  List<bool> get correct => [for (var i = 0; i < fields.length; i++) fields[i].value == answers[i]];

  @override
  Outcome evaluate() {
    if (fields.any((f) => f.value == null)) return const Outcome.failed('empty');
    final ok = correct;
    final wrong = ok.where((c) => !c).length;
    if (wrong == 0) return const Outcome.solved();
    return Outcome.failed(
      fields.length == 1 ? 'wrong' : 'some_wrong',
      magnitude: wrong.toDouble(),
      detail: {'wrong': wrong},
    );
  }

  @override
  SimResult simulate() {
    final outcome = evaluate();
    final b = TimelineBuilder(48);
    final ok = correct;
    for (var i = 0; i < fields.length; i++) {
      b.ramp('reveal$i', 4 + i * 6, 16 + i * 6);
      b.fill('ok$i', (_) => ok[i] ? 1 : 0);
    }
    if (outcome.success) {
      b.spring('pop', target: 1, omega: 12, damping: 0.4, delay: 10);
    } else {
      b.spring('shake', target: 0, velocity: 6, omega: 32, damping: 0.15, delay: 8);
    }
    return SimResult(outcome, b.build());
  }
}

class AnswerArchetype extends Archetype {
  const AnswerArchetype();

  @override
  String get id => 'answer';

  @override
  AnswerScene create(LevelSpec level) => AnswerScene(level);

  @override
  Solution? solve(LevelSpec level) {
    final scene = create(level);
    return Solution({'values': scene.answers}, effort: scene.fields.length);
  }

  @override
  double? winFraction(LevelSpec level) {
    final scene = create(level);
    return scene.fields.fold<double>(1, (p, f) => p / f.space);
  }
}
