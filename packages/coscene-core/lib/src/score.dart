/// cosIQ: one headline number for a player's progress, on a 70-160 scale.
///
/// It is a game score, not a measured IQ. Every solved level adds its
/// difficulty, weighted by its stars; the total is taken as a share of
/// everything on offer and mapped onto the scale.
const int scoreFloor = 70;
const int scoreCeiling = 160;

/// How much of a level's worth each star count earns.
double starWeight(int stars) => switch (stars) {
  >= 3 => 1.0,
  2 => 0.8,
  1 => 0.6,
  _ => 0.0,
};

int cosIq({required Iterable<({int difficulty, int stars})> solved, required int totalDifficulty}) {
  if (totalDifficulty <= 0) return scoreFloor;
  var earned = 0.0;
  for (final s in solved) {
    earned += s.difficulty * starWeight(s.stars);
  }
  final share = (earned / totalDifficulty).clamp(0.0, 1.0);
  return scoreFloor + ((scoreCeiling - scoreFloor) * share).round();
}

/// Lowest score of each rank, from rank 1 upward.
const List<int> rankThresholds = [70, 85, 100, 115, 130, 145];

/// Rank 1 to 6 for a score. Titles live in the dictionary as `rank.<n>`.
int rankFor(int score) {
  var rank = 1;
  for (var i = 0; i < rankThresholds.length; i++) {
    if (score >= rankThresholds[i]) rank = i + 1;
  }
  return rank;
}

/// Points still needed for the next rank, or null at the top.
int? pointsToNextRank(int score) {
  final rank = rankFor(score);
  return rank >= rankThresholds.length ? null : rankThresholds[rank] - score;
}
