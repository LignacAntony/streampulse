import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Principe S : SecureStorage a une seule responsabilité — persister les tokens JWT.
// Principe I : interface fine (5 méthodes ciblées, pas de méthode générique exposée).
class SecureStorage {
  // Android : depuis flutter_secure_storage v10, le chiffrement repose sur des
  // ciphers custom (la lib EncryptedSharedPreferences de Jetpack Security étant
  // dépréciée par Google) ; les données existantes sont migrées au premier accès.
  // Plus de `aOptions` à passer : l'ancien `encryptedSharedPreferences` est ignoré.
  SecureStorage() : _storage = const FlutterSecureStorage();

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
