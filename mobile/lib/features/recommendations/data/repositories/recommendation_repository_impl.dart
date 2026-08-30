import '../../domain/entities/recommended_track.dart';
import '../../domain/repositories/recommendation_repository.dart';
import '../datasources/recommendation_remote_data_source.dart';

/// Implémente [RecommendationRepository] au-dessus de la source distante.
class RecommendationRepositoryImpl implements RecommendationRepository {
  RecommendationRepositoryImpl(this._remote);

  final RecommendationRemoteDataSource _remote;

  @override
  Future<List<RecommendedTrack>> fetch() => _remote.fetch();
}
