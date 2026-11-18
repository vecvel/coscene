import 'package:coscene_core/coscene_core.dart';

import 'generators.dart';
import 'places.dart';

/// Place number used for daily scenes. They sit outside the normal chapters.
const int dailyPlace = 0;

String dailyKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

/// The scene of the day. Built on the device from the date alone, so every
/// player gets the same puzzle and no server is involved. The engine solves
/// it before it is returned.
LevelSpec dailyLevel(DateTime date, {Engine? engine}) {
  final key = dailyKey(date);
  final seed = Rng.hash('coscene-daily-$key');
  final dayNumber = DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/ 86400000;
  final topic = basePlaces[dayNumber % basePlaces.length];
  return generateLevel(
    id: 'daily-$key',
    place: dailyPlace,
    index: 1 + Rng(seed).nextInt(levelsPerPlace),
    topic: topic.id,
    difficulty: baseDifficulty(topic.number, 6),
    seed: seed,
    engine: engine,
  );
}
