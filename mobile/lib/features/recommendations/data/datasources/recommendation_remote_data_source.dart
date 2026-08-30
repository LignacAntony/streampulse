import 'package:dio/dio.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_error_mapper.dart';
import '../../../playlists/domain/entities/track.dart';
import '../../domain/entities/recommended_track.dart';

/// Appelle `GET /api/recommendations/tracks` (US-09-04).
///
/// ⚠️ **Volontairement hors du client généré** (même choix que la sonde de
/// manifeste, ADR 045/046) : régénérer tout le paquet `streampulse_api` pour un
/// unique endpoint bonus produirait un large diff de code généré pour un gain
/// nul. On passe par le `Dio` sous-jacent — **même instance**, donc mêmes
/// intercepteurs (auth `Bearer`, trace, log) et même `baseUrl`.
class RecommendationRemoteDataSource {
  RecommendationRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<RecommendedTrack>> fetch() async {
    try {
      final response = await _dio.get<List<dynamic>>(
        ApiConstants.recommendedTracks,
      );
      final data = response.data ?? const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(_fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  RecommendedTrack _fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String) {
      throw const ServerException('Recommandation malformée');
    }
    return RecommendedTrack(
      track: Track(
        id: id,
        title: title,
        artist: json['artist'] as String?,
        durationS: (json['duration_s'] as num?)?.toInt(),
      ),
      reason: json['reason'] as String? ?? '',
    );
  }
}
