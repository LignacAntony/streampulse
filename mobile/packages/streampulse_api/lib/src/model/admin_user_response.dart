//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'admin_user_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class AdminUserResponse {
  /// Returns a new [AdminUserResponse] instance.
  AdminUserResponse({
    required this.id,

    required this.email,

    required this.username,

    required this.role,

    required this.isActive,

    required this.createdAt,
  });

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'email', required: true, includeIfNull: false)
  final String email;

  @JsonKey(name: r'username', required: true, includeIfNull: false)
  final String username;

  @JsonKey(name: r'role', required: true, includeIfNull: false)
  final AdminUserResponseRoleEnum role;

  @JsonKey(name: r'is_active', required: true, includeIfNull: false)
  final bool isActive;

  @JsonKey(name: r'created_at', required: true, includeIfNull: false)
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminUserResponse &&
          other.id == id &&
          other.email == email &&
          other.username == username &&
          other.role == role &&
          other.isActive == isActive &&
          other.createdAt == createdAt;

  @override
  int get hashCode =>
      id.hashCode +
      email.hashCode +
      username.hashCode +
      role.hashCode +
      isActive.hashCode +
      createdAt.hashCode;

  factory AdminUserResponse.fromJson(Map<String, dynamic> json) =>
      _$AdminUserResponseFromJson(json);

  Map<String, dynamic> toJson() => _$AdminUserResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}

enum AdminUserResponseRoleEnum {
  @JsonValue(r'anonymous')
  anonymous(r'anonymous'),
  @JsonValue(r'user')
  user(r'user'),
  @JsonValue(r'broadcaster')
  broadcaster(r'broadcaster'),
  @JsonValue(r'admin')
  admin(r'admin');

  const AdminUserResponseRoleEnum(this.value);

  final String value;

  @override
  String toString() => value;
}
