import 'package:equatable/equatable.dart';

// Principe O : la hiérarchie est extensible par héritage sans modifier Failure.
abstract class Failure extends Equatable {
  const Failure([this.message = '']);

  final String message;

  @override
  List<Object> get props => [message];
}

class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Erreur serveur']);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Pas de connexion réseau']);
}

class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Non autorisé']);
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Erreur de cache local']);
}
