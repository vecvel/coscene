import 'dart:ui';

/// The flat, matte colours of coscene. No gradients anywhere.
abstract final class Palette {
  static const Color orange = Color(0xFFF0642B); // brand
  static const Color cream = Color(0xFFF2EDE4); // page
  static const Color white = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF23262B); // text and structure
  static const Color inkSoft = Color(0xFF5B5F66); // secondary text
  static const Color sand = Color(0xFFE4DCCD); // quiet surfaces
  static const Color stone = Color(0xFFC9BFAE); // belts, ground, disabled
  static const Color coral = Color(0xFFE4572E);
  static const Color mustard = Color(0xFFF2B134);
  static const Color teal = Color(0xFF1F8A70); // success
  static const Color slate = Color(0xFF3E5C76); // water, steel
  static const Color blue = Color(0xFF2F6BDE);

  static const Color tealTint = Color(0xFFDDEFE9);
  static const Color tealDeep = Color(0xFF085041);
  static const Color coralDeep = Color(0xFFB23A17);

  /// Colour of a named item, as used in level data.
  static Color named(String id) => switch (id) {
    'coral' => coral,
    'teal' => teal,
    'mustard' => mustard,
    'slate' => slate,
    _ => ink,
  };

  /// One accent per place, cycling.
  static Color place(int number) =>
      const [orange, slate, mustard, teal, coral, coralDeep, blue, slate, orange, teal][(number - 1) % 10];
}
