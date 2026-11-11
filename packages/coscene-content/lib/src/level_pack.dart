import 'dart:convert';

import 'package:coscene_core/coscene_core.dart';

import 'places.dart';

/// Thrown when a pack cannot be used: bad format, bad signature, levels the
/// engine cannot solve, or a pack made for a newer app.
class PackException implements Exception {
  PackException(this.message);
  final String message;

  @override
  String toString() => 'PackException: $message';
}

/// A versioned set of levels, bundled with the app or downloaded later.
///
/// Document shape:
/// ```json
/// {
///   "id": "base", "version": 1, "minEngineVersion": 1,
///   "places": [{"number": 1, "id": "dockyard", "archetypeIds": ["balance_levers"]}],
///   "levels": [ ...level objects... ],
///   "strings": {"en": {"place.dockyard.name": "Dockyard"}}
/// }
/// ```
class LevelPack {
  LevelPack({
    required this.id,
    required this.version,
    required this.minEngineVersion,
    required this.places,
    required this.levels,
    this.strings = const {},
  });

  factory LevelPack.fromJson(Map<String, dynamic> json) {
    try {
      final strings = <String, Map<String, String>>{};
      final rawStrings = json['strings'];
      if (rawStrings is Map<String, dynamic>) {
        for (final e in rawStrings.entries) {
          strings[e.key] = (e.value as Map).cast<String, String>();
        }
      }
      return LevelPack(
        id: json['id'] as String,
        version: json['version'] as int,
        minEngineVersion: json['minEngineVersion'] as int? ?? 1,
        places: [for (final p in json['places'] as List) PlaceInfo.fromJson(p as Map<String, dynamic>)],
        levels: [for (final l in json['levels'] as List) LevelSpec.fromJson(l as Map<String, dynamic>)],
        strings: strings,
      );
    } on LevelFormatException catch (e) {
      throw PackException(e.toString());
    } on TypeError catch (e) {
      throw PackException('pack does not match the schema: $e');
    }
  }

  factory LevelPack.fromBytes(List<int> bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (e) {
      throw PackException('pack is not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) throw PackException('pack must be a JSON object');
    return LevelPack.fromJson(decoded);
  }

  final String id;
  final int version;

  /// Oldest engine that can play this pack.
  final int minEngineVersion;
  final List<PlaceInfo> places;
  final List<LevelSpec> levels;

  /// Extra dictionary entries by language code, for text the app does not
  /// already ship (new places, seasonal objectives).
  final Map<String, Map<String, String>> strings;

  Map<String, dynamic> toJson() => {
    'id': id,
    'version': version,
    'minEngineVersion': minEngineVersion,
    'places': [for (final p in places) p.toJson()],
    'levels': [for (final l in levels) l.toJson()],
    if (strings.isNotEmpty) 'strings': strings,
  };

  /// Checks every level against the engine. Returns the problems found,
  /// one line each; empty means the pack is safe to play.
  List<String> verify(Engine engine) {
    final problems = <String>[];
    if (minEngineVersion > engineVersion) {
      problems.add('pack needs engine $minEngineVersion, this app has $engineVersion');
      return problems;
    }
    final ids = <String>{};
    final placeNumbers = {for (final p in places) p.number};
    for (final level in levels) {
      if (!ids.add(level.id)) problems.add('${level.id}: duplicate id');
      if (!placeNumbers.contains(level.place)) problems.add('${level.id}: unknown place ${level.place}');
      for (final issue in engine.inspect(level).issues) {
        problems.add('${level.id}: $issue');
      }
    }
    return problems;
  }
}
