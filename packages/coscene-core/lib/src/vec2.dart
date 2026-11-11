import 'dart:math' as math;

/// Immutable 2D vector in scene units.
class Vec2 {
  const Vec2(this.x, this.y);

  factory Vec2.fromDegrees(double degrees, [double length = 1]) {
    final r = degrees * math.pi / 180;
    return Vec2(math.cos(r) * length, math.sin(r) * length);
  }

  final double x;
  final double y;

  static const zero = Vec2(0, 0);

  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(double s) => Vec2(x * s, y * s);
  Vec2 operator -() => Vec2(-x, -y);

  double dot(Vec2 o) => x * o.x + y * o.y;
  double cross(Vec2 o) => x * o.y - y * o.x;
  double get length => math.sqrt(x * x + y * y);
  double distanceTo(Vec2 o) => (this - o).length;

  Vec2 get normalized {
    final l = length;
    return l == 0 ? zero : Vec2(x / l, y / l);
  }

  /// Perpendicular vector, rotated a quarter turn.
  Vec2 get perpendicular => Vec2(-y, x);

  /// Mirror this direction about a surface with the given unit normal.
  Vec2 reflect(Vec2 normal) => this - normal * (2 * dot(normal));

  Vec2 lerp(Vec2 o, double t) => Vec2(x + (o.x - x) * t, y + (o.y - y) * t);

  List<double> toJson() => [x, y];

  @override
  bool operator ==(Object other) => other is Vec2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

/// A straight wall, mirror or edge between two points.
class Segment {
  const Segment(this.a, this.b);
  final Vec2 a;
  final Vec2 b;

  Vec2 get direction => (b - a).normalized;
  Vec2 get normal => direction.perpendicular;
}

/// Distance along a ray (origin + dir * t) at which it meets [s], or null.
double? raySegment(Vec2 origin, Vec2 dir, Segment s, {double epsilon = 1e-6}) {
  final e = s.b - s.a;
  final denom = dir.cross(e);
  if (denom.abs() < 1e-12) return null;
  final diff = s.a - origin;
  final t = diff.cross(e) / denom;
  final u = diff.cross(dir) / denom;
  if (t <= epsilon || u < 0 || u > 1) return null;
  return t;
}

/// Distance along a ray at which it first enters a circle, or null.
double? rayCircle(Vec2 origin, Vec2 dir, Vec2 center, double radius, {double epsilon = 1e-6}) {
  final oc = origin - center;
  final b = oc.dot(dir);
  final c = oc.dot(oc) - radius * radius;
  final disc = b * b - c;
  if (disc < 0) return null;
  final root = math.sqrt(disc);
  final t1 = -b - root;
  if (t1 > epsilon) return t1;
  final t2 = -b + root;
  if (t2 > epsilon) return t2;
  return null;
}

/// Shortest distance from [p] to the segment [a]-[b].
double pointSegmentDistance(Vec2 p, Vec2 a, Vec2 b) {
  final ab = b - a;
  final len2 = ab.dot(ab);
  if (len2 == 0) return p.distanceTo(a);
  final t = ((p - a).dot(ab) / len2).clamp(0.0, 1.0);
  return p.distanceTo(a + ab * t);
}
