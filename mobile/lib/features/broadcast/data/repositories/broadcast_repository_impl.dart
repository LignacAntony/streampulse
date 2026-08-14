import '../../domain/entities/broadcast_stats.dart';
import '../../domain/entities/broadcast_stream.dart';
import '../../domain/repositories/broadcast_repository.dart';
import '../datasources/broadcast_remote_data_source.dart';
import '../mappers/broadcast_dto_mappers.dart';

/// Implémentation du contrat diffuseur au-dessus de l'API générée. Sa seule
/// responsabilité est la traduction DTO -> entité : la gestion d'erreurs vit
/// dans le datasource, la logique d'état dans `BroadcastNotifier`.
class BroadcastRepositoryImpl implements BroadcastRepository {
  BroadcastRepositoryImpl(this._remote);

  final BroadcastRemoteDataSource _remote;

  @override
  Future<List<BroadcastStream>> listMyStreams() async {
    final dtos = await _remote.listMyStreams();
    return dtos.map((dto) => dto.toBroadcastEntity()).toList();
  }

  @override
  Future<BroadcastStream> createStream({
    required String title,
    required bool isPublic,
    String? description,
    String? category,
  }) async {
    final dto = await _remote.createStream(
      title: title,
      isPublic: isPublic,
      description: description,
      category: category,
    );
    return dto.toBroadcastEntity();
  }

  @override
  Future<BroadcastStream> startStream(String id) async {
    final dto = await _remote.startStream(id);
    return dto.toBroadcastEntity();
  }

  @override
  Future<BroadcastStream> stopStream(String id) async {
    final dto = await _remote.stopStream(id);
    return dto.toBroadcastEntity();
  }

  @override
  Future<BroadcastStream> rotateStreamKey(String id) async {
    final dto = await _remote.rotateStreamKey(id);
    return dto.toBroadcastEntity();
  }

  @override
  Future<void> deleteStream(String id) => _remote.deleteStream(id);

  @override
  Future<BroadcastStats> streamStats(String id) async {
    final dto = await _remote.streamStats(id);
    return dto.toEntity();
  }
}
