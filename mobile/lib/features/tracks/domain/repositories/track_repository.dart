import '../../../playlists/domain/entities/track.dart';

/// Contrat de la bibliothèque de pistes (US-05-01). L'entité `Track` est
/// partagée avec la feature playlists (même ressource côté API).
abstract class TrackRepository {
  /// Uploade un fichier audio dans la bibliothèque du demandeur et renvoie la
  /// piste créée. [onProgress] reçoit l'avancement de l'envoi (0.0 → 1.0).
  Future<Track> upload({
    required String filePath,
    required String filename,
    required String title,
    String? artist,
    int? durationS,
    void Function(double progress)? onProgress,
  });
}
