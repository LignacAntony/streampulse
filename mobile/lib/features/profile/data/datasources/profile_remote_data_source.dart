import 'package:dio/dio.dart';
import 'package:streampulse_api/streampulse_api.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_error_mapper.dart';

class ProfileRemoteDataSource {
  ProfileRemoteDataSource(this._profileApi);

  final ProfileApi _profileApi;

  Future<ProfileResponse> getMe() async {
    try {
      final response = await _profileApi.getMyProfile();
      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return body;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<ProfileResponse> update(UpdateProfileRequest request) async {
    try {
      final response = await _profileApi.updateMyProfile(
        updateProfileRequest: request,
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return body;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
