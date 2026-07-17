import '../../domain/entities/live_stream.dart';
import '../../domain/repositories/stream_repository.dart';
import '../datasources/stream_remote_data_source.dart';
import '../mappers/stream_dto_mappers.dart';

class StreamRepositoryImpl implements StreamRepository {
  StreamRepositoryImpl(this._remote);

  final StreamRemoteDataSource _remote;

  @override
  Future<List<LiveStream>> listLiveStreams({
    int limit = 20,
    int offset = 0,
  }) async {
    final dtos = await _remote.listLive(limit: limit, offset: offset);
    return dtos.map((dto) => dto.toEntity()).toList();
  }
}
