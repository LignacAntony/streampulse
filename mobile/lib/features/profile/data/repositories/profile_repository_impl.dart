import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';
import '../datasources/profile_remote_data_source.dart';
import '../models/user_profile_model.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  ProfileRepositoryImpl(this._remote);

  final ProfileRemoteDataSource _remote;

  @override
  Future<UserProfile> getMe() async {
    final model = await _remote.getMe();
    return model.toEntity();
  }

  @override
  Future<UserProfile> update(UserProfile profile) async {
    final model = await _remote.update(UserProfileModel.fromEntity(profile));
    return model.toEntity();
  }
}
