import 'package:dio/dio.dart';
import 'package:streampulse_api/streampulse_api.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_error_mapper.dart';

/// Encapsule le `PlaylistApi` généré et traduit les `DioException` en
/// exceptions typées (cf. `mapDioException`). Un 409 est étiqueté avec un
/// message métier par défaut (nom déjà utilisé).
///
/// La bibliothèque de pistes (`libraryTracks`) passe par le `TrackApi` : depuis
/// l'extraction du domaine track (US-05-01), `GET /api/tracks` n'appartient plus
/// au tag Playlist du contrat OpenAPI.
class PlaylistRemoteDataSource {
  PlaylistRemoteDataSource(this._api, this._trackApi);

  final PlaylistApi _api;
  final TrackApi _trackApi;

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

  Future<void> favorite(String id) async {
    try {
      await _api.addPlaylistFavorite(id: id);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> unfavorite(String id) async {
    try {
      await _api.removePlaylistFavorite(id: id);
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

  Future<List<TrackResponse>> libraryTracks() async {
    try {
      final response = await _trackApi.listUserTracks();
      return response.data?.toList() ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<List<PlaylistTrackResponse>> addTrack(
    String playlistId,
    String trackId,
  ) async {
    try {
      final response = await _api.addPlaylistTrack(
        id: playlistId,
        addPlaylistTrackRequest: AddPlaylistTrackRequest(trackId: trackId),
      );
      return response.data?.toList() ?? const [];
    } on DioException catch (e) {
      // Pas de `conflictMessage` : les 409 des pistes portent toujours un
      // message serveur, que `mapDioException` préfère de toute façon à un
      // repli client. En poser un ici dupliquerait la chaîne backend sans
      // jamais l'afficher.
      throw mapDioException(e);
    }
  }

  Future<void> removeTrack(String playlistId, String trackId) async {
    try {
      await _api.removePlaylistTrack(id: playlistId, trackId: trackId);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<List<PlaylistTrackResponse>> reorderTracks(
    String playlistId,
    List<String> trackIds,
  ) async {
    try {
      final response = await _api.reorderPlaylistTracks(
        id: playlistId,
        reorderPlaylistTracksRequest: ReorderPlaylistTracksRequest(
          trackIds: trackIds,
        ),
      );
      return response.data?.toList() ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
