import 'package:dio/dio.dart';
import 'package:streampulse_api/streampulse_api.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_error_mapper.dart';

/// Encapsule le `PlaylistApi` généré et traduit les `DioException` en
/// exceptions typées (cf. `mapDioException`). Un 409 est étiqueté avec un
/// message métier par défaut (nom déjà utilisé).
class PlaylistRemoteDataSource {
  PlaylistRemoteDataSource(this._api);

  final PlaylistApi _api;

  static const _duplicateNameMessage = 'Une playlist porte déjà ce nom';

  Future<List<PlaylistResponse>> list() async {
    try {
      final response = await _api.listPlaylists();
      return response.data?.toList() ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<PlaylistResponse> create(String name, String? description) async {
    try {
      final response = await _api.createPlaylist(
        createPlaylistRequest: CreatePlaylistRequest(
          name: name,
          description: description,
        ),
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return body;
    } on DioException catch (e) {
      throw mapDioException(e, conflictMessage: _duplicateNameMessage);
    }
  }

  Future<PlaylistResponse> rename(
    String id,
    String name,
    String? description,
  ) async {
    try {
      final response = await _api.updatePlaylist(
        id: id,
        updatePlaylistRequest: UpdatePlaylistRequest(
          name: name,
          description: description,
        ),
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return body;
    } on DioException catch (e) {
      throw mapDioException(e, conflictMessage: _duplicateNameMessage);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _api.deletePlaylist(id: id);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<List<PlaylistTrackResponse>> tracks(String id) async {
    try {
      final response = await _api.listPlaylistTracks(id: id);
      return response.data?.toList() ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
