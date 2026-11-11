import 'dart:convert';

import 'generated/locales.g.dart';
import 'languages.dart';

/// The text of one language, with English behind it for anything missing.
class Dictionary {
  Dictionary(this.languageCode, Map<String, String> entries, {Map<String, String>? fallback})
    : _entries = entries,
      _fallback = fallback ?? const {};

  final String languageCode;
  final Map<String, String> _entries;
  final Map<String, String> _fallback;

  static final RegExp _placeholder = RegExp(r'\{(\w+)\}');

  bool has(String key) => _entries.containsKey(key);

  Iterable<String> get keys => _entries.keys;

  /// The text for [key] with `{name}` placeholders filled from [params].
  /// Falls back to English, then to the key itself, so a missing entry is
  /// visible on screen instead of crashing.
  String t(String key, [Map<String, Object?> params = const {}]) {
    final text = _entries[key] ?? _fallback[key] ?? key;
    if (params.isEmpty) return text;
    return text.replaceAllMapped(_placeholder, (m) {
      final value = params[m.group(1)];
      return value == null ? m.group(0)! : value.toString();
    });
  }

  /// A copy with extra entries on top, for text that arrives in level packs.
  Dictionary withExtra(Map<String, String> extra) =>
      extra.isEmpty ? this : Dictionary(languageCode, {..._entries, ...extra}, fallback: _fallback);
}

/// Loads dictionaries for the supported languages.
class LocaleManager {
  LocaleManager._();
  static final LocaleManager instance = LocaleManager._();

  final Map<String, Map<String, String>> _cache = {};

  /// The raw entries of one language. Parsed once, then kept.
  Map<String, String> entries(String code) => _cache.putIfAbsent(code, () {
    final source = localeJson[code];
    if (source == null) throw ArgumentError('no dictionary for "$code"');
    return (jsonDecode(source) as Map<String, dynamic>).cast<String, String>();
  });

  /// The dictionary for [code], or English when the code is not supported.
  Dictionary dictionary(String code) {
    final lang = isSupported(code) ? code : fallbackLanguage;
    return Dictionary(lang, entries(lang), fallback: lang == fallbackLanguage ? null : entries(fallbackLanguage));
  }
}
