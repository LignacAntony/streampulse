//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'admin_metrics_users.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class AdminMetricsUsers {
  /// Returns a new [AdminMetricsUsers] instance.
  AdminMetricsUsers({
    required this.total,

    required this.active,

    required this.broadcasters,

    required this.admins,
  });

  @JsonKey(name: r'total', required: true, includeIfNull: false)
  final int total;

  /// Accounts with is_active true.
  @JsonKey(name: r'active', required: true, includeIfNull: false)
  final int active;

  @JsonKey(name: r'broadcasters', required: true, includeIfNull: false)
  final int broadcasters;

  @JsonKey(name: r'admins', required: true, includeIfNull: false)
  final int admins;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminMetricsUsers &&
          other.total == total &&
          other.active == active &&
          other.broadcasters == broadcasters &&
          other.admins == admins;

  @override
  int get hashCode =>
      total.hashCode +
      active.hashCode +
      broadcasters.hashCode +
      admins.hashCode;

  factory AdminMetricsUsers.fromJson(Map<String, dynamic> json) =>
      _$AdminMetricsUsersFromJson(json);

  Map<String, dynamic> toJson() => _$AdminMetricsUsersToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
