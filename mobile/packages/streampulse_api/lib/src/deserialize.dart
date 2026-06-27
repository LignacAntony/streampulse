import 'package:streampulse_api/src/model/create_stream_request.dart';
import 'package:streampulse_api/src/model/error_detail.dart';
import 'package:streampulse_api/src/model/error_response.dart';
import 'package:streampulse_api/src/model/forgot_password_request.dart';
import 'package:streampulse_api/src/model/health_response.dart';
import 'package:streampulse_api/src/model/login_request.dart';
import 'package:streampulse_api/src/model/logout_request.dart';
import 'package:streampulse_api/src/model/message_response.dart';
import 'package:streampulse_api/src/model/profile_response.dart';
import 'package:streampulse_api/src/model/refresh_request.dart';
import 'package:streampulse_api/src/model/register_request.dart';
import 'package:streampulse_api/src/model/reset_password_request.dart';
import 'package:streampulse_api/src/model/stream_response.dart';
import 'package:streampulse_api/src/model/stream_summary_response.dart';
import 'package:streampulse_api/src/model/token_pair_response.dart';
import 'package:streampulse_api/src/model/update_profile_request.dart';
import 'package:streampulse_api/src/model/user_response.dart';

final _regList = RegExp(r'^List<(.*)>$');
final _regSet = RegExp(r'^Set<(.*)>$');
final _regMap = RegExp(r'^Map<String,(.*)>$');

ReturnType deserialize<ReturnType, BaseType>(
  dynamic value,
  String targetType, {
  bool growable = true,
}) {
  switch (targetType) {
    case 'String':
      return '$value' as ReturnType;
    case 'int':
      return (value is int ? value : int.parse('$value')) as ReturnType;
    case 'bool':
      if (value is bool) {
        return value as ReturnType;
      }
      final valueString = '$value'.toLowerCase();
      return (valueString == 'true' || valueString == '1') as ReturnType;
    case 'double':
      return (value is double ? value : double.parse('$value')) as ReturnType;
    case 'CreateStreamRequest':
      return CreateStreamRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'ErrorDetail':
      return ErrorDetail.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'ErrorResponse':
      return ErrorResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'ForgotPasswordRequest':
      return ForgotPasswordRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'HealthResponse':
      return HealthResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'LoginRequest':
      return LoginRequest.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'LogoutRequest':
      return LogoutRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'MessageResponse':
      return MessageResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'ProfileResponse':
      return ProfileResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'RefreshRequest':
      return RefreshRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'RegisterRequest':
      return RegisterRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'ResetPasswordRequest':
      return ResetPasswordRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'StreamResponse':
      return StreamResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'StreamSummaryResponse':
      return StreamSummaryResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'TokenPairResponse':
      return TokenPairResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'UpdateProfileRequest':
      return UpdateProfileRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'UserResponse':
      return UserResponse.fromJson(value as Map<String, dynamic>) as ReturnType;
    default:
      RegExpMatch? match;

      if (value is List && (match = _regList.firstMatch(targetType)) != null) {
        targetType = match![1]!; // ignore: parameter_assignments
        return value
                .map<BaseType>(
                  (dynamic v) => deserialize<BaseType, BaseType>(
                    v,
                    targetType,
                    growable: growable,
                  ),
                )
                .toList(growable: growable)
            as ReturnType;
      }
      if (value is Set && (match = _regSet.firstMatch(targetType)) != null) {
        targetType = match![1]!; // ignore: parameter_assignments
        return value
                .map<BaseType>(
                  (dynamic v) => deserialize<BaseType, BaseType>(
                    v,
                    targetType,
                    growable: growable,
                  ),
                )
                .toSet()
            as ReturnType;
      }
      if (value is Map && (match = _regMap.firstMatch(targetType)) != null) {
        targetType = match![1]!.trim(); // ignore: parameter_assignments
        return Map<String, BaseType>.fromIterables(
              value.keys as Iterable<String>,
              value.values.map(
                (dynamic v) => deserialize<BaseType, BaseType>(
                  v,
                  targetType,
                  growable: growable,
                ),
              ),
            )
            as ReturnType;
      }
      break;
  }
  throw Exception('Cannot deserialize');
}
