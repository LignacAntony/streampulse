//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'stream_stats_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class StreamStatsResponse {
  /// Returns a new [StreamStatsResponse] instance.
  StreamStatsResponse({
    required this.streamId,

    required this.status,

    required this.listeners,

    required this.peakListeners,

    this.startedAt,

    required this.durationSeconds,
  });

  @JsonKey(name: r'stream_id', required: true, includeIfNull: false)
  final String streamId;

  @JsonKey(name: r'status', required: true, includeIfNull: false)
  final StreamStatsResponseStatusEnum status;

  /// Estimated number of distinct clients that fetched the manifest recently. Zero when the stream is not live.
  @JsonKey(name: r'listeners', required: true, includeIfNull: false)
  final int listeners;

  /// Highest `listeners` value observed since the broadcast started. In-memory only: reset on process restart, lost when the stream ends.
  @JsonKey(name: r'peak_listeners', required: true, includeIfNull: false)
  final int peakListeners;

  @JsonKey(name: r'started_at', required: false, includeIfNull: false)
  final DateTime? startedAt;

  /// Seconds since `started_at` — up to now while live, up to `ended_at` once the broadcast is over. Zero if the stream never started.
  @JsonKey(name: r'duration_seconds', required: true, includeIfNull: false)
  final int durationSeconds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamStatsResponse &&
          other.streamId == streamId &&
          other.status == status &&
          other.listeners == listeners &&
          other.peakListeners == peakListeners &&
          other.startedAt == startedAt &&
          other.durationSeconds == durationSeconds;

  @override
  int get hashCode =>
      streamId.hashCode +
      status.hashCode +
      listeners.hashCode +
      peakListeners.hashCode +
      (startedAt == null ? 0 : startedAt.hashCode) +
      durationSeconds.hashCode;

  factory StreamStatsResponse.fromJson(Map<String, dynamic> json) =>
      _$StreamStatsResponseFromJson(json);

  Map<String, dynamic> toJson() => _$StreamStatsResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}

enum StreamStatsResponseStatusEnum {
  @JsonValue(r'idle')
  idle(r'idle'),
  @JsonValue(r'live')
  live(r'live'),
  @JsonValue(r'ended')
  ended(r'ended');

  const StreamStatsResponseStatusEnum(this.value);

  final String value;

  @override
  String toString() => value;
}
