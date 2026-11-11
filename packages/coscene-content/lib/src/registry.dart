import 'dart:convert';

import 'package:coscene_core/coscene_core.dart';

import 'generated/base_pack.g.dart';
import 'level_pack.dart';
import 'places.dart';

/// The 100 levels shipped inside the app, playable with no connection.
LevelPack loadBundledPack() => LevelPack.fromJson(jsonDecode(basePackJson) as Map<String, dynamic>);

/// Every level the app can currently play, from the bundled pack plus any
/// downloaded packs. Later packs replace levels and places with the same id.
class LevelRegistry {
  LevelRegistry({Engine? engine}) : engine = engine ?? Engine.standard;

  factory LevelRegistry.bundled({Engine? engine}) => LevelRegistry(engine: engine)..add(loadBundledPack());

  final Engine engine;
  final Map<int, PlaceInfo> _places = {};
  final Map<String, LevelSpec> _levels = {};
  final Map<String, int> _packVersions = {};
  final Map<String, Map<String, String>> _strings = {};

  /// Adds a pack. Set [verify] for packs that did not ship with the app:
  /// a pack with any unsolvable or malformed level is refused whole.
  void add(LevelPack pack, {bool verify = false}) {
    if (pack.minEngineVersion > engineVersion) {
      throw PackException('pack "${pack.id}" needs a newer app');
    }
    if (verify) {
      final problems = pack.verify(engine);
      if (problems.isNotEmpty) {
        throw PackException('pack "${pack.id}" refused: ${problems.take(3).join('; ')}');
      }
    }
    for (final p in pack.places) {
      _places[p.number] = p;
    }
    for (final l in pack.levels) {
      if (!engine.supports(l.archetypeId)) continue;
      _levels[l.id] = l;
    }
    for (final e in pack.strings.entries) {
      _strings.putIfAbsent(e.key, () => {}).addAll(e.value);
    }
    _packVersions[pack.id] = pack.version;
  }

  Map<String, int> get packVersions => Map.unmodifiable(_packVersions);

  /// Dictionary entries that arrived with packs, for one language.
  Map<String, String> extraStrings(String languageCode) => _strings[languageCode] ?? const {};

  List<PlaceInfo> get places => _places.values.toList()..sort((a, b) => a.number.compareTo(b.number));

  PlaceInfo? place(int number) => _places[number];

  List<LevelSpec> get levels =>
      _levels.values.toList()
        ..sort((a, b) => a.place != b.place ? a.place.compareTo(b.place) : a.index.compareTo(b.index));

  List<LevelSpec> levelsOf(int place) =>
      _levels.values.where((l) => l.place == place).toList()..sort((a, b) => a.index.compareTo(b.index));

  LevelSpec? byId(String id) => _levels[id];

  /// The level that follows [level], in the same place or the next one.
  LevelSpec? next(LevelSpec level) {
    final all = levels;
    final i = all.indexWhere((l) => l.id == level.id);
    return i >= 0 && i + 1 < all.length ? all[i + 1] : null;
  }

  int get count => _levels.length;
}
