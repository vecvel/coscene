/// Thrown when level data does not match the schema.
class LevelFormatException implements Exception {
  LevelFormatException(this.message, {this.levelId});
  final String message;
  final String? levelId;

  @override
  String toString() => levelId == null ? 'LevelFormatException: $message' : 'LevelFormatException($levelId): $message';
}

/// The schema version this engine reads.
const int levelSchemaVersion = 1;

/// One level, exactly as it appears in a JSON pack.
class LevelSpec {
  LevelSpec({
    required this.id,
    required this.archetypeId,
    required this.place,
    required this.index,
    required this.difficulty,
    required this.initialState,
    required this.validationRules,
    required this.hints,
    required this.i18nKey,
    required this.conceptId,
    this.textParams = const {},
    this.schemaVersion = levelSchemaVersion,
  });

  factory LevelSpec.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw LevelFormatException('"id" must be a non-empty string');
    }
    T need<T>(String key) {
      final v = json[key];
      if (v is! T) {
        throw LevelFormatException('"$key" must be ${T.toString()}', levelId: id);
      }
      return v;
    }

    final version = json['schemaVersion'] ?? levelSchemaVersion;
    if (version is! int || version < 1 || version > levelSchemaVersion) {
      throw LevelFormatException('unsupported schemaVersion $version', levelId: id);
    }
    final hints = need<List<dynamic>>('hints');
    if (hints.isEmpty || hints.any((h) => h is! String)) {
      throw LevelFormatException('"hints" must be a non-empty list of keys', levelId: id);
    }
    final params = json['textParams'] ?? const <String, dynamic>{};
    if (params is! Map<String, dynamic>) {
      throw LevelFormatException('"textParams" must be an object', levelId: id);
    }
    return LevelSpec(
      id: id,
      schemaVersion: version,
      archetypeId: need<String>('archetypeId'),
      place: need<int>('place'),
      index: need<int>('index'),
      difficulty: need<int>('difficulty'),
      initialState: need<Map<String, dynamic>>('initialState'),
      validationRules: need<Map<String, dynamic>>('validationRules'),
      hints: hints.cast<String>(),
      i18nKey: need<String>('i18nKey'),
      conceptId: need<String>('conceptId'),
      textParams: params,
    );
  }

  final String id;
  final int schemaVersion;

  /// Interaction pattern, for example `balance_levers`.
  final String archetypeId;

  /// 1-based place (chapter) and position inside it.
  final int place;
  final int index;

  /// 1 (gentle) to 10 (hard).
  final int difficulty;

  final Map<String, dynamic> initialState;
  final Map<String, dynamic> validationRules;

  /// Dictionary keys of the progressive hints, mildest first.
  final List<String> hints;

  /// Base dictionary key. `<i18nKey>.objective` and `<i18nKey>.reveal` must exist.
  final String i18nKey;

  /// The idea named on the reveal sheet. `concept.<conceptId>.*` must exist.
  final String conceptId;

  /// Values substituted into localized text, for example `{turns}`.
  final Map<String, dynamic> textParams;

  String get objectiveKey => '$i18nKey.objective';
  String get revealKey => '$i18nKey.reveal';

  Map<String, dynamic> toJson() => {
    'id': id,
    'schemaVersion': schemaVersion,
    'archetypeId': archetypeId,
    'place': place,
    'index': index,
    'difficulty': difficulty,
    'i18nKey': i18nKey,
    'conceptId': conceptId,
    if (textParams.isNotEmpty) 'textParams': textParams,
    'hints': hints,
    'initialState': initialState,
    'validationRules': validationRules,
  };
}

/// Typed access to a JSON object with clear errors.
class JsonReader {
  JsonReader(this.map, this.levelId, [this.path = '']);
  final Map<String, dynamic> map;
  final String levelId;
  final String path;

  Never _fail(String key, String expected) =>
      throw LevelFormatException('"$path$key" must be $expected', levelId: levelId);

  bool has(String key) => map[key] != null;

  double number(String key, {double? orElse}) {
    final v = map[key];
    if (v is num) return v.toDouble();
    if (v == null && orElse != null) return orElse;
    _fail(key, 'a number');
  }

  double? numberOrNull(String key) {
    final v = map[key];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    _fail(key, 'a number or null');
  }

  int integer(String key, {int? orElse}) {
    final v = map[key];
    if (v is int) return v;
    if (v == null && orElse != null) return orElse;
    _fail(key, 'an integer');
  }

  int? integerOrNull(String key) {
    final v = map[key];
    if (v == null) return null;
    if (v is int) return v;
    _fail(key, 'an integer or null');
  }

  bool boolean(String key, {bool? orElse}) {
    final v = map[key];
    if (v is bool) return v;
    if (v == null && orElse != null) return orElse;
    _fail(key, 'true or false');
  }

  String string(String key, {String? orElse}) {
    final v = map[key];
    if (v is String) return v;
    if (v == null && orElse != null) return orElse;
    _fail(key, 'a string');
  }

  String? stringOrNull(String key) {
    final v = map[key];
    if (v == null) return null;
    if (v is String) return v;
    _fail(key, 'a string or null');
  }

  JsonReader object(String key) {
    final v = map[key];
    if (v is Map<String, dynamic>) return JsonReader(v, levelId, '$path$key.');
    _fail(key, 'an object');
  }

  JsonReader? objectOrNull(String key) => map[key] == null ? null : object(key);

  List<dynamic> list(String key, {bool optional = false}) {
    final v = map[key];
    if (v is List) return v;
    if (v == null && optional) return const [];
    _fail(key, 'a list');
  }

  List<JsonReader> objects(String key, {bool optional = false}) {
    final items = list(key, optional: optional);
    return [
      for (var i = 0; i < items.length; i++)
        if (items[i] is Map<String, dynamic>)
          JsonReader(items[i] as Map<String, dynamic>, levelId, '$path$key[$i].')
        else
          _fail('$key[$i]', 'an object'),
    ];
  }

  List<int> integers(String key, {bool optional = false}) {
    final items = list(key, optional: optional);
    if (items.any((e) => e is! int)) _fail(key, 'a list of integers');
    return items.cast<int>();
  }

  List<String> strings(String key, {bool optional = false}) {
    final items = list(key, optional: optional);
    if (items.any((e) => e is! String)) _fail(key, 'a list of strings');
    return items.cast<String>();
  }
}
