import '../entities/user_profile.dart';

abstract class ProfileRepository {
  Future<UserProfile> getMe();

  Future<UserProfile> update(UserProfile profile);
}
