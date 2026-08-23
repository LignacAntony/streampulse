import 'package:streampulse_api/src/model/add_playlist_track_request.dart';
import 'package:streampulse_api/src/model/admin_chat_message.dart';
import 'package:streampulse_api/src/model/admin_global_banned_user.dart';
import 'package:streampulse_api/src/model/admin_metrics_http.dart';
import 'package:streampulse_api/src/model/admin_metrics_response.dart';
import 'package:streampulse_api/src/model/admin_metrics_streams.dart';
import 'package:streampulse_api/src/model/admin_metrics_users.dart';
import 'package:streampulse_api/src/model/admin_stream_list_response.dart';
import 'package:streampulse_api/src/model/admin_stream_response.dart';
import 'package:streampulse_api/src/model/admin_user_list_response.dart';
import 'package:streampulse_api/src/model/admin_user_response.dart';
import 'package:streampulse_api/src/model/broadcaster_request_admin.dart';
import 'package:streampulse_api/src/model/broadcaster_request_input.dart';
import 'package:streampulse_api/src/model/broadcaster_request_list_response.dart';
import 'package:streampulse_api/src/model/broadcaster_request_response.dart';
import 'package:streampulse_api/src/model/create_playlist_request.dart';
import 'package:streampulse_api/src/model/create_stream_request.dart';
import 'package:streampulse_api/src/model/delete_account_request.dart';
import 'package:streampulse_api/src/model/error_detail.dart';
import 'package:streampulse_api/src/model/error_response.dart';
import 'package:streampulse_api/src/model/forgot_password_request.dart';
import 'package:streampulse_api/src/model/global_ban_user_request.dart';
import 'package:streampulse_api/src/model/health_response.dart';
import 'package:streampulse_api/src/model/login_request.dart';
import 'package:streampulse_api/src/model/logout_request.dart';
import 'package:streampulse_api/src/model/message_response.dart';
import 'package:streampulse_api/src/model/playlist_response.dart';
import 'package:streampulse_api/src/model/playlist_track_response.dart';
import 'package:streampulse_api/src/model/profile_response.dart';
import 'package:streampulse_api/src/model/refresh_request.dart';
import 'package:streampulse_api/src/model/register_request.dart';
import 'package:streampulse_api/src/model/reorder_playlist_tracks_request.dart';
import 'package:streampulse_api/src/model/reset_password_request.dart';
import 'package:streampulse_api/src/model/review_request_input.dart';
import 'package:streampulse_api/src/model/set_user_active_request.dart';
import 'package:streampulse_api/src/model/stream_response.dart';
import 'package:streampulse_api/src/model/stream_stats_response.dart';
import 'package:streampulse_api/src/model/stream_summary_response.dart';
import 'package:streampulse_api/src/model/token_pair_response.dart';
import 'package:streampulse_api/src/model/track_response.dart';
import 'package:streampulse_api/src/model/update_playlist_request.dart';
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
    case 'AddPlaylistTrackRequest':
      return AddPlaylistTrackRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'AdminChatMessage':
      return AdminChatMessage.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'AdminGlobalBannedUser':
      return AdminGlobalBannedUser.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'AdminMetricsHTTP':
      return AdminMetricsHTTP.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'AdminMetricsResponse':
      return AdminMetricsResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'AdminMetricsStreams':
      return AdminMetricsStreams.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'AdminMetricsUsers':
      return AdminMetricsUsers.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'AdminStreamListResponse':
      return AdminStreamListResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'AdminStreamResponse':
      return AdminStreamResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'AdminUserListResponse':
      return AdminUserListResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'AdminUserResponse':
      return AdminUserResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'BroadcasterRequestAdmin':
      return BroadcasterRequestAdmin.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'BroadcasterRequestInput':
      return BroadcasterRequestInput.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'BroadcasterRequestListResponse':
      return BroadcasterRequestListResponse.fromJson(
            value as Map<String, dynamic>,
          )
          as ReturnType;
    case 'BroadcasterRequestResponse':
      return BroadcasterRequestResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'CreatePlaylistRequest':
      return CreatePlaylistRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'CreateStreamRequest':
      return CreateStreamRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'DeleteAccountRequest':
      return DeleteAccountRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'ErrorDetail':
      return ErrorDetail.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'ErrorResponse':
      return ErrorResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'ForgotPasswordRequest':
      return ForgotPasswordRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'GlobalBanUserRequest':
      return GlobalBanUserRequest.fromJson(value as Map<String, dynamic>)
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
    case 'PlaylistResponse':
      return PlaylistResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'PlaylistTrackResponse':
      return PlaylistTrackResponse.fromJson(value as Map<String, dynamic>)
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
    case 'ReorderPlaylistTracksRequest':
      return ReorderPlaylistTracksRequest.fromJson(
            value as Map<String, dynamic>,
          )
          as ReturnType;
    case 'ResetPasswordRequest':
      return ResetPasswordRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'ReviewRequestInput':
      return ReviewRequestInput.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'SetUserActiveRequest':
      return SetUserActiveRequest.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'StreamResponse':
      return StreamResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'StreamStatsResponse':
      return StreamStatsResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'StreamSummaryResponse':
      return StreamSummaryResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'TokenPairResponse':
      return TokenPairResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'TrackResponse':
      return TrackResponse.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'UpdatePlaylistRequest':
      return UpdatePlaylistRequest.fromJson(value as Map<String, dynamic>)
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
