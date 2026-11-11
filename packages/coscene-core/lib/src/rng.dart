/// Small seeded generator (mulberry32). It gives the same sequence on every
/// device and Dart version, which level generation and daily scenes rely on.
class Rng {
  Rng(int seed) : _state = seed & _mask;

  static const int _mask = 0xFFFFFFFF;
  int _state;

  static int _imul(int a, int b) {
    final lo = (a & 0xFFFF) * b;
    final hi = ((a >>> 16) * b) & 0xFFFF;
    return (lo + (hi << 16)) & _mask;
  }

  int nextU32() {
    _state = (_state + 0x6D2B79F5) & _mask;
    var t = _state;
    t = _imul(t ^ (t >>> 15), t | 1);
    t = (t ^ (t + _imul(t ^ (t >>> 7), t | 61))) & _mask;
    return (t ^ (t >>> 14)) & _mask;
  }

  /// Uniform in [0, 1).
  double nextDouble() => nextU32() / 4294967296.0;

  /// Uniform integer in [0, max).
  int nextInt(int max) => max <= 0 ? 0 : (nextDouble() * max).floor();

  /// Uniform integer in [min, max], both included.
  int range(int min, int max) => min + nextInt(max - min + 1);

  bool chance(double p) => nextDouble() < p;

  T pick<T>(List<T> items) => items[nextInt(items.length)];

  void shuffle<T>(List<T> items) {
    for (var i = items.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = items[i];
      items[i] = items[j];
      items[j] = tmp;
    }
  }

  /// Stable 32-bit hash of a string, for turning ids and dates into seeds.
  static int hash(String text) {
    var h = 0x811C9DC5;
    for (final unit in text.codeUnits) {
      h ^= unit;
      h = _imul(h, 0x01000193);
    }
    return h;
  }
}
