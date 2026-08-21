import 'package:shared_preferences/shared_preferences.dart';

/// Persistance du niveau sonore choisi par l'auditeur (STR-245).
///
/// Interface séparée de l'implémentation (principe D) pour la même raison que
/// `AudioPlaybackService` : le noyau audio n'a pas à connaître le magasin, et
/// les tests n'ont pas à faire tourner de plugin de plateforme.
///
/// Ce n'est **pas** [SecureStorage] : celui-ci n'a qu'une responsabilité, les
/// jetons JWT, et un niveau sonore n'est ni un secret ni quelque chose qu'on
/// veut chiffrer.
abstract class VolumeStore {
  /// Niveau enregistré dans `[0, 1]`, ou `null` si l'auditeur n'a jamais réglé
  /// le volume — auquel cas l'appelant garde le défaut du lecteur.
  Future<double?> read();

  Future<void> write(double volume);
}

/// Implémentation sur `shared_preferences`.
class SharedPreferencesVolumeStore implements VolumeStore {
  const SharedPreferencesVolumeStore();

  static const _key = 'playback_volume';

  @override
  Future<double?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getDouble(_key);
    if (stored == null) return null;
    // Une valeur hors bornes ne peut venir que d'une écriture d'une autre
    // version de l'application, ou d'un fichier de préférences trafiqué.
    // `setVolume` la refuserait : on la ramène plutôt que de laisser
    // l'application démarrer sur une exception.
    return stored.clamp(0.0, 1.0);
  }

  @override
  Future<void> write(double volume) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, volume.clamp(0.0, 1.0));
  }
}

/// Magasin en mémoire, pour les tests et les plateformes sans plugin.
class InMemoryVolumeStore implements VolumeStore {
  InMemoryVolumeStore([this._volume]);

  double? _volume;

  @override
  Future<double?> read() async => _volume;

  @override
  Future<void> write(double volume) async => _volume = volume.clamp(0.0, 1.0);
}
