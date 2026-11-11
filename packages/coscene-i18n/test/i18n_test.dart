import 'dart:convert';
import 'dart:io';

import 'package:coscene_i18n/coscene_i18n.dart';
import 'package:test/test.dart';

void main() {
  final manager = LocaleManager.instance;
  final placeholder = RegExp(r'\{\w+\}');

  test('eight languages, each with its own name', () {
    expect(supportedLanguages.map((l) => l.code), ['en', 'hi', 'bn', 'as', 'ta', 'te', 'id', 'ko']);
    expect(supportedLanguages.map((l) => l.nativeName).toSet(), hasLength(8));
  });

  test('every language has every key, with the same placeholders', () {
    final en = manager.entries('en');
    expect(en.length, greaterThan(300));
    for (final lang in supportedLanguages) {
      final entries = manager.entries(lang.code);
      expect(entries.keys.toSet(), en.keys.toSet(), reason: lang.code);
      for (final key in en.keys) {
        expect(entries[key]!.trim(), isNotEmpty, reason: '${lang.code}: $key');
        final want = placeholder.allMatches(en[key]!).map((m) => m.group(0)).toList()..sort();
        final got = placeholder.allMatches(entries[key]!).map((m) => m.group(0)).toList()..sort();
        expect(got, want, reason: '${lang.code}: $key');
      }
    }
  });

  test('translations are really translated', () {
    final en = manager.entries('en');
    for (final lang in supportedLanguages.where((l) => l.code != 'en')) {
      final entries = manager.entries(lang.code);
      final same = en.keys.where((k) => en[k]!.length > 14 && entries[k] == en[k]).toList();
      expect(same, isEmpty, reason: '${lang.code} still has English for $same');
    }
  });

  test('each script is the one its language is written in', () {
    bool uses(String code, int from, int to) =>
        manager.entries(code)['ui.settings']!.runes.any((r) => r >= from && r <= to);
    expect(uses('hi', 0x0900, 0x097F), isTrue);
    expect(uses('bn', 0x0980, 0x09FF), isTrue);
    expect(uses('as', 0x0980, 0x09FF), isTrue);
    expect(uses('ta', 0x0B80, 0x0BFF), isTrue);
    expect(uses('te', 0x0C00, 0x0C7F), isTrue);
    expect(uses('ko', 0xAC00, 0xD7AF), isTrue);
    // Assamese is told apart from Bengali by its own letters.
    final assamese = manager.entries('as').values.join();
    expect(assamese.contains('ৰ') || assamese.contains('ৱ'), isTrue);
  });

  test('embedded dictionaries match the JSON files', () {
    for (final lang in supportedLanguages) {
      final onDisk = (jsonDecode(File('locales/${lang.code}.json').readAsStringSync()) as Map).cast<String, String>();
      expect(manager.entries(lang.code), onDisk, reason: 'run: dart run tool/embed_locales.dart');
    }
  });

  test('placeholders are filled and missing text falls back safely', () {
    final hi = manager.dictionary('hi');
    expect(hi.t('ui.scene_number', {'number': 7}), contains('7'));
    expect(hi.t('ui.scene_number', {'number': 7}), isNot(contains('{')));
    final partial = Dictionary('xx', const {'a': 'A {n}'}, fallback: const {'b': 'B'});
    expect(partial.t('a', {'n': 2}), 'A 2');
    expect(partial.t('b'), 'B', reason: 'falls back to English');
    expect(partial.t('c'), 'c', reason: 'shows the key rather than crashing');
    expect(partial.withExtra(const {'c': 'C'}).t('c'), 'C');
  });

  test('the device language picks the game language', () {
    expect(resolveLanguage(['fr', 'ta-IN', 'en']), 'ta');
    expect(resolveLanguage(['ko_KR']), 'ko');
    expect(resolveLanguage(['fr', 'de']), 'en');
    expect(resolveLanguage([]), 'en');
    expect(manager.dictionary('fr').languageCode, 'en');
  });
}
