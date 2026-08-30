// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_metrics_users.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AdminMetricsUsers _$AdminMetricsUsersFromJson(Map<String, dynamic> json) =>
    $checkedCreate('AdminMetricsUsers', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['total', 'active', 'broadcasters', 'admins'],
      );
      final val = AdminMetricsUsers(
        total: $checkedConvert('total', (v) => (v as num).toInt()),
        active: $checkedConvert('active', (v) => (v as num).toInt()),
        broadcasters: $checkedConvert(
          'broadcasters',
          (v) => (v as num).toInt(),
        ),
        admins: $checkedConvert('admins', (v) => (v as num).toInt()),
      );
      return val;
    });

Map<String, dynamic> _$AdminMetricsUsersToJson(AdminMetricsUsers instance) =>
    <String, dynamic>{
      'total': instance.total,
      'active': instance.active,
      'broadcasters': instance.broadcasters,
      'admins': instance.admins,
    };
