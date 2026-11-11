import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coscene_content/coscene_content.dart';
import 'package:coscene_core/coscene_core.dart';
import 'package:coscene_i18n/coscene_i18n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/audio.dart';
import '../services/save_store.dart';

/// What the player achieved on one level.
class LevelRecord {
  LevelRecord({required this.stars, required this.attempts, required this.hints});

  factory LevelRecord.fromJson(Map<String, dynamic> j) => LevelRecord(
    stars: (j['stars'] as int? ?? 1).clamp(1, 3),
    attempts: j['attempts'] as int? ?? 1,
    hints: j['hints'] as int? ?? 0,
  );

  int stars;
  int attempts;
  int hints;

  Map<String, dynamic> toJson() => {'stars': stars, 'attempts': attempts, 'hints': hints};
}

/// How many levels of a place must be solved to open the next one.
const int levelsToOpenNextPlace = 7;

/// Testing only: build with `--dart-define=COSCENE_UNLOCK_ALL=true` to open
/// every place and scene. Off in normal builds.
const bool unlockAllForTesting = bool.fromEnvironment('COSCENE_UNLOCK_ALL');

/// Everything the screens share: levels, progress, language and settings.
class GameState extends ChangeNotifier {
  GameState._(this._store, this.registry);

  /// Reads the save and builds the level registry. [deviceLanguages] picks
  /// the language on first launch.
  static Future<GameState> load(SaveStore store, {Iterable<String> deviceLanguages = const []}) async {
    final game = GameState._(store, LevelRegistry.bundled());
    final raw = await store.read();
    if (raw != null) {
      try {
        game._restore(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // An unreadable save starts fresh rather than crashing at launch.
      }
    }
    game._language ??= resolveLanguage(deviceLanguages);
    game._rebuildDictionary();
    return game;
  }

  final SaveStore _store;
  final LevelRegistry registry;
  final AudioPlayer audio = AudioPlayer();

  final Map<String, LevelRecord> _records = {};
  String? _language;
  late Dictionary _dictionary;

  String name = '';
  bool sound = true;
  bool haptics = true;
  bool reduceMotion = false;
  bool leftHanded = false;
  String? dailyLast;
  int dailyStreak = 0;

  /// True once a sync brought in levels the player has not seen yet.
  bool newScenesReady = false;

  // ---------------------------------------------------------------- text

  String get language => _language ?? fallbackLanguage;

  String t(String key, [Map<String, Object?> params = const {}]) => _dictionary.t(key, params);

  void _rebuildDictionary() {
    _dictionary = LocaleManager.instance.dictionary(language).withExtra(registry.extraStrings(language));
  }

  void setLanguage(String code) {
    if (!isSupported(code) || code == _language) return;
    _language = code;
    _rebuildDictionary();
    _changed();
  }

  String shortName(LevelSpec level) => archetypeShortNames[level.archetypeId] ?? level.archetypeId;
  String objective(LevelSpec level) => t(level.objectiveKey, level.textParams);
  String placeName(int number) =>
      number == dailyPlace ? t('place.daily.name') : t('place.${registry.place(number)?.id}.name');

  // ------------------------------------------------------------ progress

  LevelRecord? record(String levelId) => _records[levelId];
  bool isSolved(String levelId) => _records.containsKey(levelId);
  int starsOf(String levelId) => _records[levelId]?.stars ?? 0;

  int solvedIn(int place) => registry.levelsOf(place).where((l) => isSolved(l.id)).length;
  int starsIn(int place) => registry.levelsOf(place).fold(0, (a, l) => a + starsOf(l.id));

  bool isPlaceOpen(int place) {
    if (unlockAllForTesting) return true;
    final places = registry.places;
    final i = places.indexWhere((p) => p.number == place);
    if (i <= 0) return true;
    return solvedIn(places[i - 1].number) >= levelsToOpenNextPlace;
  }

  bool isLevelOpen(LevelSpec level) {
    if (level.place == dailyPlace || unlockAllForTesting) return true;
    if (!isPlaceOpen(level.place)) return false;
    final levels = registry.levelsOf(level.place);
    final i = levels.indexWhere((l) => l.id == level.id);
    return i <= 0 || isSolved(levels[i - 1].id);
  }

  /// The first open level that is not solved yet, or null when all are done.
  LevelSpec? get nextUp {
    for (final level in registry.levels) {
      if (!isSolved(level.id) && isLevelOpen(level)) return level;
    }
    return null;
  }

  int get totalSolved => registry.levels.where((l) => isSolved(l.id)).length;
  int get totalStars => registry.levels.fold(0, (a, l) => a + starsOf(l.id));

  /// Every idea in the game, in the order levels introduce them.
  List<String> get allConcepts {
    final seen = <String>{};
    return [
      for (final l in registry.levels)
        if (seen.add(l.conceptId)) l.conceptId,
    ];
  }

  Set<String> get foundConcepts => {
    for (final l in registry.levels)
      if (isSolved(l.id)) l.conceptId,
  };

  int get score => cosIq(
    solved: [
      for (final l in registry.levels)
        if (isSolved(l.id)) (difficulty: l.difficulty, stars: starsOf(l.id)),
    ],
    totalDifficulty: registry.levels.fold(0, (a, l) => a + l.difficulty),
  );

  int get rank => rankFor(score);

  /// Saves a solve. Returns true when it uncovered an idea for the first time.
  bool recordSolve(PlaySession session) {
    final level = session.level;
    if (level.place == dailyPlace) {
      _recordDaily();
      _changed();
      return false;
    }
    final isNewIdea = !foundConcepts.contains(level.conceptId);
    final old = _records[level.id];
    if (old == null || session.stars > old.stars) {
      _records[level.id] = LevelRecord(stars: session.stars, attempts: session.attempts, hints: session.hintsUsed);
    }
    _changed();
    return isNewIdea;
  }

  // --------------------------------------------------------------- daily

  String get todayKey => dailyKey(DateTime.now());
  bool get dailyDone => dailyLast == todayKey;

  void _recordDaily() {
    final today = todayKey;
    if (dailyLast == today) return;
    final yesterday = dailyKey(DateTime.now().subtract(const Duration(days: 1)));
    dailyStreak = dailyLast == yesterday ? dailyStreak + 1 : 1;
    dailyLast = today;
  }

  /// The streak as it stands today: it lapses after a missed day.
  int get currentStreak {
    final yesterday = dailyKey(DateTime.now().subtract(const Duration(days: 1)));
    return dailyLast == todayKey || dailyLast == yesterday ? dailyStreak : 0;
  }

  // ------------------------------------------------------------ settings

  void update(void Function() change) {
    change();
    _changed();
  }

  Future<void> resetProgress() async {
    _records.clear();
    dailyLast = null;
    dailyStreak = 0;
    _changed();
  }

  // --------------------------------------------------------- sound, feel

  void play(Sfx sfx) {
    if (sound) audio.play(sfx);
  }

  void buzz([int strength = 0]) {
    if (!haptics) return;
    switch (strength) {
      case 0:
        HapticFeedback.selectionClick();
      case 1:
        HapticFeedback.lightImpact();
      case 2:
        HapticFeedback.mediumImpact();
      default:
        HapticFeedback.heavyImpact();
    }
  }

  // -------------------------------------------------------- remote packs

  /// Loads packs downloaded earlier, then looks for new ones. Does nothing
  /// unless the app was built with a pack URL.
  Future<void> syncPacks(Directory folder) async {
    final loader = RemotePackLoader(
      baseUrl: RemoteConfig.baseUrl,
      transport: HttpPackTransport(),
      store: DirectoryPackStore(folder),
      publicKey: RemoteConfig.publicKey,
      engine: registry.engine,
    );
    if (!loader.enabled) return;
    Future<bool> adopt() async {
      var added = false;
      for (final pack in await loader.loadCached()) {
        if (registry.packVersions[pack.id] == pack.version) continue;
        registry.add(pack);
        added = true;
      }
      return added;
    }

    if (await adopt()) {
      _rebuildDictionary();
      notifyListeners();
    }
    final report = await loader.sync();
    if (report.updated.isNotEmpty && await adopt()) {
      newScenesReady = true;
      _rebuildDictionary();
      notifyListeners();
    }
  }

  // --------------------------------------------------------------- saving

  Map<String, dynamic> _toJson() => {
    'v': 1,
    'levels': {for (final e in _records.entries) e.key: e.value.toJson()},
    'name': name,
    'language': _language,
    'sound': sound,
    'haptics': haptics,
    'reduceMotion': reduceMotion,
    'leftHanded': leftHanded,
    'dailyLast': dailyLast,
    'dailyStreak': dailyStreak,
  };

  void _restore(Map<String, dynamic> j) {
    final levels = j['levels'];
    if (levels is Map<String, dynamic>) {
      for (final e in levels.entries) {
        _records[e.key] = LevelRecord.fromJson(e.value as Map<String, dynamic>);
      }
    }
    name = j['name'] as String? ?? '';
    final lang = j['language'];
    if (lang is String && isSupported(lang)) _language = lang;
    sound = j['sound'] as bool? ?? true;
    haptics = j['haptics'] as bool? ?? true;
    reduceMotion = j['reduceMotion'] as bool? ?? false;
    leftHanded = j['leftHanded'] as bool? ?? false;
    dailyLast = j['dailyLast'] as String?;
    dailyStreak = j['dailyStreak'] as int? ?? 0;
  }

  Future<void> _pending = Future.value();

  void _changed() {
    notifyListeners();
    final snapshot = jsonEncode(_toJson());
    // Writes are queued so a slow one can never overwrite a newer save.
    _pending = _pending.then((_) => _store.write(snapshot)).catchError((_) {});
  }

  /// Completes when every queued save has reached storage.
  Future<void> get saved => _pending;
}
