import 'package:equatable/equatable.dart';

import '../../../playlists/domain/entities/track.dart';

class PublicTrack extends Equatable {
  const PublicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.durationS,
    required this.ownerName,
  });

  final String id;
  final String title;
  final String? artist;
  final int? durationS;
  final String ownerName;

  Track toTrack() => Track(
        id: id,
        title: title,
        artist: artist,
        durationS: durationS,
        isPublic: true,
      );

  @override
  List<Object?> get props => [id, title, artist, durationS, ownerName];
}
