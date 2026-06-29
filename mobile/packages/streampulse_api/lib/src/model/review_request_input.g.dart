// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_request_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReviewRequestInput _$ReviewRequestInputFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReviewRequestInput', json, ($checkedConvert) {
      final val = ReviewRequestInput(
        reviewNote: $checkedConvert('review_note', (v) => v as String?),
      );
      return val;
    }, fieldKeyMap: const {'reviewNote': 'review_note'});

Map<String, dynamic> _$ReviewRequestInputToJson(ReviewRequestInput instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('review_note', instance.reviewNote);
  return val;
}
