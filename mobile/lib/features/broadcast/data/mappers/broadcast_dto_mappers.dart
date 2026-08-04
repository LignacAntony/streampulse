import 'package:streampulse_api/streampulse_api.dart';

import '../../domain/entities/broadcast_stats.dart';
import '../../domain/entities/broadcast_stream.dart';

/// Conversion du DTO généré vers l'entité domaine : le type généré ne franchit
/// pas la couche data (cf. les mappers de `features/streams` et `auth`).
extension StreamResponseBroadcastMapper on StreamResponse {
  BroadcastStream toBroadcastEntity() => BroadcastStream(
        id: id,
        title: title,
        status: status.value,
        isPublic: isPublic,
        createdAt: createdAt,
        description: description,
        category: category,
        startedAt: startedAt,
        streamKey: streamKey,
        streamSourceUrl: streamSourceUrl,
      );
}

extension StreamStatsResponseMapper on StreamStatsResponse {
  /// `durationSeconds` du DTO n'est pas repris : cf. [BroadcastStats].
  BroadcastStats toEntity() => BroadcastStats(
        streamId: streamId,
        listeners: listeners,
        peak: peakListeners,
      );
}

/// Traduit une catégorie du domaine (chaîne libre) vers l'énumération générée.
///
/// Une valeur hors de la liste blanche est envoyée comme « pas de catégorie »
/// plutôt que de provoquer un 400 : le formulaire ne propose que des valeurs
/// valides, donc ce cas ne se produit que si le backend en retire une.
CreateStreamRequestCategoryEnum? streamCategoryToDto(String? category) {
  if (category == null) return null;
  for (final value in CreateStreamRequestCategoryEnum.values) {
    if (value.value == category) return value;
  }
  return null;
}
