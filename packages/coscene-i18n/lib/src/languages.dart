/// One language the game ships in.
class Language {
  const Language(this.code, this.nativeName, this.englishName);

  /// ISO 639-1 code, also the name of its dictionary file.
  final String code;

  /// The language's name written in itself, shown in the language picker.
  final String nativeName;
  final String englishName;
}

/// The eight languages of coscene. All of them are drawn with the fonts
/// already on the phone; the app bundles no font files.
const List<Language> supportedLanguages = [
  Language('en', 'English', 'English'),
  Language('hi', 'हिन्दी', 'Hindi'),
  Language('bn', 'বাংলা', 'Bengali'),
  Language('as', 'অসমীয়া', 'Assamese'),
  Language('ta', 'தமிழ்', 'Tamil'),
  Language('te', 'తెలుగు', 'Telugu'),
  Language('id', 'Bahasa Indonesia', 'Indonesian'),
  Language('ko', '한국어', 'Korean'),
];

const String fallbackLanguage = 'en';

bool isSupported(String code) => supportedLanguages.any((l) => l.code == code);

/// Picks the game language for a device: the first of the phone's preferred
/// languages that the game speaks, else English.
String resolveLanguage(Iterable<String> preferredCodes) {
  for (final raw in preferredCodes) {
    final code = raw.toLowerCase().split(RegExp('[-_]')).first;
    if (isSupported(code)) return code;
  }
  return fallbackLanguage;
}
