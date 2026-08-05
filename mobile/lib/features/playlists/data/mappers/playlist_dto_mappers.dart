import 'package:streampulse_api/streampulse_api.dart';

import '../../domain/entities/playlist.dart';
import '../../domain/entities/playlist_track.dart';
import '../../domain/entities/track.dart';

/// Conversions DTO généré (package `streampulse_api`) → entités domaine.
/// Confine la dépendance au client généré à la couche data.
extension PlaylistResponseMapper on PlaylistResponse {
  Playlist toEntity() => Playlist(
        id: id,
        name: name,
        description: description,
        isPublic: isPublic,
        trackCount: trackCount,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

extension TrackResponseMapper on TrackResponse {
  Track toEntity() => Track(
        id: id,
        title: title,
        artist: artist,
        durationS: durationS,
      );
}

extension PlaylistTrackResponseMapper on PlaylistTrackResponse {
  PlaylistTrack toEntity() => PlaylistTrack(
        id: id,
        title: title,
        artist: artist,
        durationS: durationS,
        position: position,
      );
}
