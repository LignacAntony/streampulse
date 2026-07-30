import '../entities/broadcast_stream.dart';

/// Contrat de la couche données du tableau de bord diffuseur (US-06-01).
///
/// Interface volontairement étroite (principe I) : le dashboard n'a besoin que
/// de lister ses propres flux et de piloter leur cycle de vie. La suppression
/// et la mise à jour d'un flux relèvent d'autres écrans et n'ont pas à être
/// exposées ici.
abstract class BroadcastRepository {
  /// Flux du diffuseur connecté, tous statuts confondus (idle/live/ended),
  /// archivés exclus. Renvoie une liste vide pour un utilisateur qui n'a pas
  /// le rôle diffuseur — ce n'est pas une erreur.
  Future<List<BroadcastStream>> listMyStreams();

  /// Crée un flux à l'état `idle`. [title] doit respecter
  /// [kStreamTitleMinLength]/[kStreamTitleMaxLength], [category] appartenir à
  /// [kStreamCategories].
  Future<BroadcastStream> createStream({
    required String title,
    required bool isPublic,
    String? description,
    String? category,
  });

  /// Passe le flux `idle` -> `live`. Lève une `ConflictException` si un autre
  /// flux du diffuseur est déjà en direct (un seul live par diffuseur).
  Future<BroadcastStream> startStream(String id);

  /// Passe le flux `live` -> `ended`. Lève une `ConflictException` si le flux
  /// n'était pas en direct (arrêt concurrent par un admin, par exemple).
  Future<BroadcastStream> stopStream(String id);
}
