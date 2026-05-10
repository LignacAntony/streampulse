import '../entities/token_pair.dart';
import '../entities/user.dart';

abstract class AuthRepository {
  Future<User> register({
    required String email,
    required String username,
    required String password,
  });

  Future<TokenPair> login({
    required String email,
    required String password,
  });
}
