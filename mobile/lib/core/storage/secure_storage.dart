import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Principe S : SecureStorage a une seule responsabilité — persister les tokens JWT.
// Principe I : interface fine (5 méthodes ciblées, pas de méthode générique exposée).
class SecureStorage {
  SecureStorage()
      : _storage = const FlutterSecureStorage(
          // Utilise EncryptedSharedPreferences sur Android (API 23+)
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  final FlutterSecureStorage _storage;

  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';

  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _keyAccessToken, value: token);

  Future<void> saveRefreshToken(String token) =>
      _storage.write(key: _keyRefreshToken, value: token);

  Future<String?> getAccessToken() => _storage.read(key: _keyAccessToken);

  Future<String?> getRefreshToken() => _storage.read(key: _keyRefreshToken);

  Future<void> clearTokens() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
  }
}
