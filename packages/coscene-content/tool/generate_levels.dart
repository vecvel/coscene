// Builds the bundled 100-level pack.
//
//   dart run tool/generate_levels.dart           regenerate levels, then embed
//   dart run tool/generate_levels.dart --embed   only re-embed the JSON files
//
// The JSON under levels/base is the source of truth. Hand edits to it are
// kept by --embed, which re-checks every level before writing the Dart file.
import 'dart:convert';
import 'dart:io';

import 'package:coscene_content/src/generators.dart';
import 'package:coscene_content/src/level_pack.dart';
import 'package:coscene_content/src/pack_io.dart';
import 'package:coscene_content/src/places.dart';
import 'package:coscene_core/coscene_core.dart';

const _levelsDir = 'levels/base';
const _generated = 'lib/src/generated/base_pack.g.dart';

void main(List<String> args) {
  if (!File('pubspec.yaml').existsSync() || !Directory('tool').existsSync()) {
    stderr.writeln('Run this from packages/coscene-content.');
    exit(64);
  }
  final engine = Engine.standard;
  if (!args.contains('--embed')) {
    final levels = <LevelSpec>[];
    final seen = <String>{};
    for (final place in basePlaces) {
      for (var index = 1; index <= levelsPerPlace; index++) {
        final id = levelId(place.number, index);
        final archetype = place.archetypeIds[(index - 1) % place.archetypeIds.length];
        final level = generateLevel(
          id: id,
          place: place.number,
          index: index,
          archetypeId: archetype,
          difficulty: baseDifficulty(place.number, index),
          seed: Rng.hash('coscene-base-$id-v1'),
          engine: engine,
          accept: (l) => seen.add(jsonEncode(l.initialState)),
        );
        levels.add(level);
        stdout.writeln('$id  ${archetype.padRight(18)} difficulty ${level.difficulty}');
      }
    }
    writePackDirectory(
      LevelPack(id: 'base', version: 1, minEngineVersion: 1, places: basePlaces, levels: levels),
      _levelsDir,
    );
  }

  final pack = readPackDirectory(_levelsDir);
  final problems = pack.verify(engine);
  if (problems.isNotEmpty) {
    stderr.writeln('Pack has problems, nothing embedded:');
    problems.forEach(stderr.writeln);
    exit(1);
  }
  File(_generated)
    ..createSync(recursive: true)
    ..writeAsStringSync(embeddedPackSource(pack));
  stdout.writeln('Embedded ${pack.levels.length} levels in ${pack.places.length} places.');
}
