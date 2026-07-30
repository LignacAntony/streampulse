import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/broadcast_stream.dart';
import '../../domain/repositories/broadcast_repository.dart';

/// Implémentation **temporaire**, le temps que la phase 2 de STR-153 livre
/// l'endpoint `GET /api/users/me/streams` et la couche données réelle.
///
/// Pourquoi ce palier plutôt qu'un écran désactivé : la phase 1 est purement
/// mobile pour ne toucher aucun fichier partagé avec la PR #273 (STR-108) en
/// revue — `internal/streaming/`, `openapi.yaml` et le client Dart généré. Le
/// tableau de bord est donc navigable et relisible, mais sans backend derrière.
///
/// `listMyStreams` renvoie une liste vide pour que l'écran affiche son état
/// vide réel ; les mutations échouent explicitement plutôt que de simuler un
/// succès. À supprimer en phase 2, avec son enregistrement dans
/// `app_providers.dart`.
class PendingBroadcastRepository implements BroadcastRepository {
  const PendingBroadcastRepository();

  static const String _message =
      'Tableau de bord indisponible : backend en cours (STR-153 phase 2)';

  @override
  Future<List<BroadcastStream>> listMyStreams() async => const [];

  @override
  Future<BroadcastStream> createStream({
    required String title,
    required bool isPublic,
    String? description,
    String? category,
  }) async =>
      throw const ServerException(_message);

  @override
  Future<BroadcastStream> startStream(String id) async =>
      throw const ServerException(_message);

  @override
  Future<BroadcastStream> stopStream(String id) async =>
      throw const ServerException(_message);
}
