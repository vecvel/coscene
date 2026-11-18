/// A topic of the game: one concept, ten scenes. The bundled pack has thirty,
/// ten per tier, and the dictionary keys still say "place".
class PlaceInfo {
  const PlaceInfo(this.number, this.id, this.archetypeIds);

  factory PlaceInfo.fromJson(Map<String, dynamic> json) => PlaceInfo(
    json['number'] as int,
    json['id'] as String,
    (json['archetypeIds'] as List? ?? const []).cast<String>(),
  );

  final int number;

  /// Dictionary keys `place.<id>.name` and `place.<id>.tagline` must exist,
  /// and the topic's text lives under `scene.<id>`, `hint.<id>` and
  /// `concept.<id>`.
  final String id;

  /// Puzzle types used here.
  final List<String> archetypeIds;

  /// 0 easy, 1 medium, 2 hard.
  int get tier => tierOfPlace(number);

  Map<String, dynamic> toJson() => {'number': number, 'id': id, 'archetypeIds': archetypeIds};
}

/// Short names used in dictionary keys, for example `action.probe`.
const Map<String, String> archetypeShortNames = {
  'answer': 'answer',
  'probe': 'probe',
  'pick': 'pick',
  'ops': 'ops',
  'route': 'route',
};

const List<String> tierIds = ['easy', 'medium', 'hard'];

int tierOfPlace(int place) => ((place - 1) ~/ 10).clamp(0, 2);

/// The thirty topics, easiest first.
const List<PlaceInfo> basePlaces = [
  // Easy: how numbers and data behave.
  PlaceInfo(1, 'binary', ['pick', 'answer']),
  PlaceInfo(2, 'bitwise', ['answer']),
  PlaceInfo(3, 'logic', ['answer']),
  PlaceInfo(4, 'logarithms', ['answer']),
  PlaceInfo(5, 'counting', ['answer']),
  PlaceInfo(6, 'modulo', ['answer']),
  PlaceInfo(7, 'binary_search', ['probe']),
  PlaceInfo(8, 'two_pointers', ['pick']),
  PlaceInfo(9, 'stacks', ['ops']),
  PlaceInfo(10, 'queues', ['answer']),
  // Medium: the classic techniques.
  PlaceInfo(11, 'bit_tricks', ['answer']),
  PlaceInfo(12, 'sorting', ['ops']),
  PlaceInfo(13, 'hashing', ['answer']),
  PlaceInfo(14, 'recursion', ['answer']),
  PlaceInfo(15, 'sliding_window', ['pick']),
  PlaceInfo(16, 'prefix_sums', ['answer']),
  PlaceInfo(17, 'greedy', ['pick']),
  PlaceInfo(18, 'heaps', ['answer']),
  PlaceInfo(19, 'bfs', ['route']),
  PlaceInfo(20, 'combinatorics', ['answer']),
  // Hard: interview favourites and systems.
  PlaceInfo(21, 'dynamic_programming', ['answer']),
  PlaceInfo(22, 'knapsack', ['pick']),
  PlaceInfo(23, 'shortest_paths', ['route']),
  PlaceInfo(24, 'topological_sort', ['ops']),
  PlaceInfo(25, 'search_the_answer', ['answer']),
  PlaceInfo(26, 'xor_tricks', ['pick', 'answer']),
  PlaceInfo(27, 'union_find', ['answer']),
  PlaceInfo(28, 'probability', ['answer']),
  PlaceInfo(29, 'caching', ['answer']),
  PlaceInfo(30, 'rate_limiting', ['answer']),
];

const int levelsPerPlace = 10;

/// Difficulty from 1 to 9: three steps inside each tier.
int baseDifficulty(int place, int index) => tierOfPlace(place) * 3 + 1 + ((index - 1) * 3) ~/ levelsPerPlace;

String levelId(int place, int index) => 'p${place.toString().padLeft(2, '0')}-l${index.toString().padLeft(2, '0')}';
