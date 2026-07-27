import 'package:streampulse_api/streampulse_api.dart';

import '../../domain/entities/live_stream.dart';

extension StreamSummaryResponseMapper on StreamSummaryResponse {
  LiveStream toEntity() => LiveStream(
        id: id,
        title: title,
        startedAt: startedAt,
        description: description,
        category: category,
        broadcasterName: broadcasterUsername,
        listenerCount: null,
        status: status.value,
      );
}
