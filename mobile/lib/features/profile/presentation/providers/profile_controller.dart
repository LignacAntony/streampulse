import 'package:flutter/material.dart';

import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';

/// Pilote l'écran profil et expose le `themeMode` global de l'application.
/// Mises à jour optimistes : rollback + exception relayée si le `PUT` échoue.
class ProfileController extends ChangeNotifier {
  ProfileController(this._repository);

  final ProfileRepository _repository;

  UserProfile? _profile;
  bool _isLoading = false;
  bool _isSaving = false;

  UserProfile? get profile => _profile;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;

  /// Thème global, sombre par défaut tant que le profil n'est pas chargé.
  ThemeMode get themeMode {
    switch (_profile?.theme) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      case 'dark':
      default:
        return ThemeMode.dark;
    }
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      _profile = await _repository.getMe();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updatePseudo(String pseudo) =>
      _applyAndSave((p) => p.copyWith(pseudo: pseudo));

  Future<void> updateTheme(String theme) =>
      _applyAndSave((p) => p.copyWith(theme: theme));

  Future<void> updateAudioQuality(String quality) =>
      _applyAndSave((p) => p.copyWith(audioQuality: quality));

  Future<void> updateNotifications(bool enabled) =>
      _applyAndSave((p) => p.copyWith(notificationsEnabled: enabled));

  Future<void> _applyAndSave(UserProfile Function(UserProfile) mutate) async {
    final current = _profile;
    if (current == null) return;

    final previous = current;
    _profile = mutate(current);
    _isSaving = true;
    notifyListeners();

    try {
      _profile = await _repository.update(_profile!);
    } catch (e) {
      _profile = previous;
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
