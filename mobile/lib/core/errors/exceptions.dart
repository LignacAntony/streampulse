class ServerException implements Exception {
  const ServerException([this.message = 'Erreur serveur']);

  final String message;

  @override
  String toString() => 'ServerException: $message';
}

class NetworkException implements Exception {
  const NetworkException([this.message = 'Pas de connexion réseau']);

  final String message;

  @override
  String toString() => 'NetworkException: $message';
}

class AuthException implements Exception {
  const AuthException([this.message = 'Non autorisé']);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}
