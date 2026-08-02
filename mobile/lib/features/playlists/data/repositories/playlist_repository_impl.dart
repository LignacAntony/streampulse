import '../../domain/entities/playlist.dart';
import '../../domain/entities/playlist_track.dart';
import '../../domain/repositories/playlist_repository.dart';
import '../datasources/playlist_remote_data_source.dart';
import '../mappers/playlist_dto_mappers.dart';

class PlaylistRepositoryImpl implements PlaylistRepository {
  PlaylistRepositoryImpl(this._remote);

  final PlaylistRemoteDataSource _remote;

  @override
  Future<List<Playlist>> list() async {
    final dtos = await _remote.list();
    return dtos.map((d) => d.toEntity()).toList();
  }

  @override
  Future<Playlist> create(String name, String? description) async {
    final dto = await _remote.create(name, description);
    return dto.toEntity();
  }

  @override
  Future<Playlist> rename(String id, String name, String? description) async {
    final dto = await _remote.rename(id, name, description);
    return dto.toEntity();
  }

  @override
  Future<void> delete(String id) => _remote.delete(id);

  @override
  Future<List<PlaylistTrack>> tracks(String id) async {
    final dtos = await _remote.tracks(id);
    return dtos.map((d) => d.toEntity()).toList();
  }
}
