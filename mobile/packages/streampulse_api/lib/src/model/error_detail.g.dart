// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'error_detail.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ErrorDetail _$ErrorDetailFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ErrorDetail', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['code', 'message']);
      final val = ErrorDetail(
        code: $checkedConvert('code', (v) => v as String),
        message: $checkedConvert('message', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$ErrorDetailToJson(ErrorDetail instance) =>
    <String, dynamic>{'code': instance.code, 'message': instance.message};
