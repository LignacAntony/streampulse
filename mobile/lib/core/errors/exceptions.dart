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

class ValidationException implements Exception {
  const ValidationException([this.message = 'Champs invalides']);

  final String message;

  @override
  String toString() => 'ValidationException: $message';
}

class DuplicateAccountException implements Exception {
  const DuplicateAccountException([
    this.message = 'Email ou pseudo déjà utilisé',
  ]);

  final String message;

  @override
  String toString() => 'DuplicateAccountException: $message';
}
