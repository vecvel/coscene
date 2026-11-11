import 'dart:convert';

import 'generated/pack_key.g.dart';

/// Build-time settings for remote level packs.
class RemoteConfig {
  /// Folder URL of the content server. Set at build time with
  /// `--dart-define=COSCENE_PACK_URL=https://cdn.example.com/coscene/`.
  /// Left empty, the app plays its bundled levels and never goes online.
  static const String packUrl = String.fromEnvironment('COSCENE_PACK_URL');

  static Uri? get baseUrl {
    if (packUrl.isEmpty) return null;
    final uri = Uri.tryParse(packUrl);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty ? uri : null;
  }

  /// Public half of the pack signing key (see tool/keygen.dart).
  static List<int> get publicKey => base64Decode(packSigningPublicKey);
}
