import '../entities/broadcaster_request.dart';

/// Contrat de la feature « demande de rôle diffuseur » (principe D).
///
/// Interface minimale (principe I) : seules les opérations côté utilisateur
/// sont exposées. La validation admin se fait via l'API/back-office web et ne
/// fait pas partie de l'app mobile.
abstract class BroadcasterRepository {
  /// Soumet une demande de rôle diffuseur pour l'utilisateur courant.
  Future<BroadcasterRequest> requestBroadcaster({String message});

  /// Récupère la dernière demande de l'utilisateur, ou `null` s'il n'en a
  /// jamais soumis (404 côté backend).
  Future<BroadcasterRequest?> getMyRequest();
}
