// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'global_ban_user_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GlobalBanUserRequest _$GlobalBanUserRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('GlobalBanUserRequest', json, ($checkedConvert) {
  final val = GlobalBanUserRequest(
    reason: $checkedConvert('reason', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$GlobalBanUserRequestToJson(
  GlobalBanUserRequest instance,
) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('reason', instance.reason);
  return val;
}
