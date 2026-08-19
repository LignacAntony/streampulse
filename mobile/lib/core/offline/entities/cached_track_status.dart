import 'package:equatable/equatable.dart';

enum TrackCacheStatus { pending, downloading, done, error }

class CachedTrackStatus extends Equatable {
  const CachedTrackStatus({
    required this.trackId,
    required this.status,
    this.progress = 0.0,
  });

  final String trackId;
  final TrackCacheStatus status;
  final double progress;

  @override
  List<Object?> get props => [trackId, status, progress];
}
