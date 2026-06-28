// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'delete_account_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeleteAccountRequest _$DeleteAccountRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('DeleteAccountRequest', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['password']);
  final val = DeleteAccountRequest(
    password: $checkedConvert('password', (v) => v as String),
  );
  return val;
});

Map<String, dynamic> _$DeleteAccountRequestToJson(
  DeleteAccountRequest instance,
) => <String, dynamic>{'password': instance.password};
