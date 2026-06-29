// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'broadcaster_request_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BroadcasterRequestInput _$BroadcasterRequestInputFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('BroadcasterRequestInput', json, ($checkedConvert) {
  final val = BroadcasterRequestInput(
    message: $checkedConvert('message', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$BroadcasterRequestInputToJson(
  BroadcasterRequestInput instance,
) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('message', instance.message);
  return val;
}
