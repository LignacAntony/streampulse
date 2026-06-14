import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/network/dio_client.dart';
import '../core/storage/secure_storage.dart';
import '../features/auth/data/datasources/auth_remote_data_source.dart';
import '../features/auth/data/repositories/auth_repository_impl.dart';
import '../features/auth/domain/repositories/auth_repository.dart';
import '../features/auth/presentation/providers/forgot_password_controller.dart';
import '../features/auth/presentation/providers/login_controller.dart';
import '../features/auth/presentation/providers/register_controller.dart';
import '../features/auth/presentation/providers/reset_password_controller.dart';
import '../features/profile/data/datasources/profile_remote_data_source.dart';
import '../features/profile/data/repositories/profile_repository_impl.dart';
import '../features/profile/domain/repositories/profile_repository.dart';
import '../features/profile/presentation/providers/profile_controller.dart';

/// Conteneur racine d'injection de dépendances (remplace `ProviderScope`).
///
/// Les dépendances infra sont des singletons paresseux (`Provider`), les
/// contrôleurs des `ChangeNotifierProvider`. Chaque `create` résout ses
/// dépendances via `context.read`, ce qui respecte le principe D (inversion
/// de dépendances) : aucun concret n'est instancié en interne.
class StreamPulseApp extends StatelessWidget {
  const StreamPulseApp({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SecureStorage>(create: (_) => SecureStorage()),
        Provider<DioClient>(
          create: (ctx) => DioClient(ctx.read<SecureStorage>()),
        ),
        Provider<AuthRemoteDataSource>(
          create: (ctx) => AuthRemoteDataSource(ctx.read<DioClient>().authApi),
        ),
        Provider<AuthRepository>(
          create: (ctx) => AuthRepositoryImpl(
            ctx.read<AuthRemoteDataSource>(),
            ctx.read<SecureStorage>(),
          ),
        ),
        ChangeNotifierProvider<LoginController>(
          create: (ctx) => LoginController(ctx.read<AuthRepository>()),
        ),
        ChangeNotifierProvider<RegisterController>(
          create: (ctx) => RegisterController(ctx.read<AuthRepository>()),
        ),
        ChangeNotifierProvider<ForgotPasswordController>(
          create: (ctx) => ForgotPasswordController(ctx.read<AuthRepository>()),
        ),
        ChangeNotifierProvider<ResetPasswordController>(
          create: (ctx) => ResetPasswordController(ctx.read<AuthRepository>()),
        ),
        Provider<ProfileRemoteDataSource>(
          create: (ctx) => ProfileRemoteDataSource(ctx.read<DioClient>()),
        ),
        Provider<ProfileRepository>(
          create: (ctx) =>
              ProfileRepositoryImpl(ctx.read<ProfileRemoteDataSource>()),
        ),
        ChangeNotifierProvider<ProfileController>(
          create: (ctx) => ProfileController(ctx.read<ProfileRepository>()),
        ),
      ],
      child: child,
    );
  }
}
