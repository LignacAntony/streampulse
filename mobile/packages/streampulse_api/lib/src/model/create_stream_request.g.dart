// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_stream_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreateStreamRequest _$CreateStreamRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('CreateStreamRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['title', 'is_public']);
      final val = CreateStreamRequest(
        title: $checkedConvert('title', (v) => v as String),
        description: $checkedConvert('description', (v) => v as String?),
        category: $checkedConvert(
          'category',
          (v) =>
              $enumDecodeNullable(_$CreateStreamRequestCategoryEnumEnumMap, v),
        ),
        isPublic: $checkedConvert('is_public', (v) => v as bool),
      );
      return val;
    }, fieldKeyMap: const {'isPublic': 'is_public'});

Map<String, dynamic> _$CreateStreamRequestToJson(CreateStreamRequest instance) {
  final val = <String, dynamic>{'title': instance.title};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('description', instance.description);
  writeNotNull(
    'category',
    _$CreateStreamRequestCategoryEnumEnumMap[instance.category],
  );
  val['is_public'] = instance.isPublic;
  return val;
}

const _$CreateStreamRequestCategoryEnumEnumMap = {
  CreateStreamRequestCategoryEnum.music: 'music',
  CreateStreamRequestCategoryEnum.talk: 'talk',
  CreateStreamRequestCategoryEnum.technology: 'technology',
  CreateStreamRequestCategoryEnum.gaming: 'gaming',
  CreateStreamRequestCategoryEnum.news: 'news',
  CreateStreamRequestCategoryEnum.sport: 'sport',
  CreateStreamRequestCategoryEnum.other: 'other',
};
