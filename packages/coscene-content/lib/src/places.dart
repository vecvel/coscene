/// A chapter of the game: one setting, ten levels.
class PlaceInfo {
  const PlaceInfo(this.number, this.id, this.archetypeIds);

  factory PlaceInfo.fromJson(Map<String, dynamic> json) => PlaceInfo(
    json['number'] as int,
    json['id'] as String,
    (json['archetypeIds'] as List? ?? const []).cast<String>(),
  );

  final int number;

  /// Dictionary keys `place.<id>.name` and `place.<id>.tagline` must exist.
  final String id;

  /// Interaction patterns used here, cycled level by level.
  final List<String> archetypeIds;

  Map<String, dynamic> toJson() => {'number': number, 'id': id, 'archetypeIds': archetypeIds};
}

/// Short names used in dictionary keys, for example `hint.balance.a.1`.
const Map<String, String> archetypeShortNames = {
  'balance_levers': 'balance',
  'ray_reflection': 'ray',
  'area_projection': 'shadow',
  'volume_flow': 'flow',
  'network_routing': 'routing',
  'permutation_locks': 'locks',
  'gear_ratio': 'gears',
  'cargo_packing': 'cargo',
};

/// The ten places of the bundled pack.
const List<PlaceInfo> basePlaces = [
  PlaceInfo(1, 'dockyard', ['balance_levers']),
  PlaceInfo(2, 'lighthouse', ['ray_reflection']),
  PlaceInfo(3, 'courtyard', ['area_projection']),
  PlaceInfo(4, 'waterworks', ['volume_flow']),
  PlaceInfo(5, 'sorting_hall', ['network_routing']),
  PlaceInfo(6, 'vault', ['permutation_locks']),
  PlaceInfo(7, 'clock_tower', ['gear_ratio']),
  PlaceInfo(8, 'harbour', ['cargo_packing']),
  PlaceInfo(9, 'workshop', ['balance_levers', 'ray_reflection', 'area_projection', 'volume_flow']),
  PlaceInfo(10, 'grand_works', ['network_routing', 'permutation_locks', 'gear_ratio', 'cargo_packing']),
];

const int levelsPerPlace = 10;

/// Difficulty (1-10) of a level by where it sits in the base pack.
int baseDifficulty(int place, int index) => place <= 8 ? 1 + (index - 1) ~/ 2 : 6 + (index - 1) ~/ 2;

/// `a` for gentle levels, `b` for the middle, `c` for the hard ones. Picks
/// which objective, hints and concept a level uses.
String tierFor(int difficulty) => difficulty <= 2 ? 'a' : (difficulty <= 5 ? 'b' : 'c');

String levelId(int place, int index) => 'p${place.toString().padLeft(2, '0')}-l${index.toString().padLeft(2, '0')}';
