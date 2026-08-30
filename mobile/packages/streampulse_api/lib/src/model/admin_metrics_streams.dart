//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'admin_metrics_streams.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class AdminMetricsStreams {
  /// Returns a new [AdminMetricsStreams] instance.
  AdminMetricsStreams({required this.live, required this.listenersEstimated});

  /// Number of streams currently broadcasting.
  @JsonKey(name: r'live', required: true, includeIfNull: false)
  final int live;

  /// Estimated listeners across all live streams. HLS has no persistent connection, so audience is inferred from recent manifest requests (ADR 025) — two listeners behind one address count as one.
  @JsonKey(name: r'listeners_estimated', required: true, includeIfNull: false)
  final int listenersEstimated;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminMetricsStreams &&
          other.live == live &&
          other.listenersEstimated == listenersEstimated;

  @override
  int get hashCode => live.hashCode + listenersEstimated.hashCode;

  factory AdminMetricsStreams.fromJson(Map<String, dynamic> json) =>
      _$AdminMetricsStreamsFromJson(json);

  Map<String, dynamic> toJson() => _$AdminMetricsStreamsToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
