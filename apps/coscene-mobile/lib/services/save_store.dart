import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the player's progress is kept.
abstract class SaveStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

/// Encrypted on the device: the iOS Keychain, and on Android an AES key
/// held in the Keystore. Nothing leaves the phone.
class SecureSaveStore implements SaveStore {
  static const _key = 'coscene.save.v1';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      // A damaged keystore entry must not lock the player out of the game.
      return null;
    }
  }

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemorySaveStore implements SaveStore {
  MemorySaveStore([this.value]);
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async => value = v;

  @override
  Future<void> clear() async => value = null;
}
