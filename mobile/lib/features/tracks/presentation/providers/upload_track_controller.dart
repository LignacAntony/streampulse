import 'package:flutter/foundation.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../playlists/domain/entities/track.dart';
import '../../domain/repositories/track_repository.dart';

/// Étapes de l'upload, pilotant l'UI (bouton, barre de progression).
enum UploadStatus { idle, uploading, success, error }

/// Pilote `UploadTrackScreen` : upload d'un fichier audio avec avancement.
///
/// L'upload est une opération longue qui peut survivre à l'écran : toutes les
/// notifications passent par [_notify], gardé par [_disposed] (même motif que
/// `PlaylistDetailController`).
class UploadTrackController extends ChangeNotifier {
  UploadTrackController(this._repository);

  final TrackRepository _repository;

  UploadStatus _status = UploadStatus.idle;
  double _progress = 0;
  String? _error;
  Track? _uploaded;
  bool _disposed = false;

  UploadStatus get status => _status;
  double get progress => _progress;
  String? get error => _error;
  Track? get uploaded => _uploaded;
  bool get isUploading => _status == UploadStatus.uploading;

  /// Uploade le fichier sélectionné. Renvoie `true` en cas de succès (l'écran
  /// affiche alors un toast et referme).
  Future<bool> upload({
    required String filePath,
    required String filename,
    required String title,
    String? artist,
    int? durationS,
    bool isPublic = false,
  }) async {
    _status = UploadStatus.uploading;
    _progress = 0;
    _error = null;
    _notify();

    try {
      final track = await _repository.upload(
        filePath: filePath,
        filename: filename,
        title: title,
        artist: artist,
        durationS: durationS,
        isPublic: isPublic,
        onProgress: (value) {
          _progress = value;
          _notify();
        },
      );
      _uploaded = track;
      _status = UploadStatus.success;
      _notify();
      return true;
    } catch (e) {
      _error = _messageFor(e);
      _status = UploadStatus.error;
      _notify();
      return false;
    }
  }

  String _messageFor(Object error) {
    if (error is NetworkException) return 'Pas de connexion réseau';
    if (error is ConflictException) return error.message;
    if (error is ValidationException) return error.message;
    if (error is ServerException) return error.message;
    return 'Échec de l\'upload';
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
