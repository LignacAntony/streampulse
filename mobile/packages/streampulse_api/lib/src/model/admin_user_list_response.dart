//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:streampulse_api/src/model/admin_user_response.dart';
import 'package:json_annotation/json_annotation.dart';

part 'admin_user_list_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class AdminUserListResponse {
  /// Returns a new [AdminUserListResponse] instance.
  AdminUserListResponse({required this.users, required this.total});

  @JsonKey(name: r'users', required: true, includeIfNull: false)
  final List<AdminUserResponse> users;

  /// Total number of users matching the filters (for pagination).
  @JsonKey(name: r'total', required: true, includeIfNull: false)
  final int total;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminUserListResponse &&
          other.users == users &&
          other.total == total;

  @override
  int get hashCode => users.hashCode + total.hashCode;

  factory AdminUserListResponse.fromJson(Map<String, dynamic> json) =>
      _$AdminUserListResponseFromJson(json);

  Map<String, dynamic> toJson() => _$AdminUserListResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
