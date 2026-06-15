import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';
import '../datasources/profile_remote_data_source.dart';
import '../mappers/profile_dto_mappers.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  ProfileRepositoryImpl(this._remote);

  final ProfileRemoteDataSource _remote;

  @override
  Future<UserProfile> getMe() async {
    final response = await _remote.getMe();
    return response.toEntity();
  }

  @override
  Future<UserProfile> update(UserProfile profile) async {
    final response = await _remote.update(profile.toUpdateRequest());
    return response.toEntity();
  }
}
