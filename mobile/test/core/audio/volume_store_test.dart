import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streampulse/core/audio/volume_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPreferencesVolumeStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('rend null tant que rien n\'a été réglé', () async {
      // null et non 1 : l'appelant garde alors le défaut du lecteur plutôt que
      // d'écrire un réglage que l'auditeur n'a jamais fait.
      expect(await const SharedPreferencesVolumeStore().read(), isNull);
    });

    test('relit ce qui a été écrit', () async {
      const store = SharedPreferencesVolumeStore();
      await store.write(0.35);
      expect(await store.read(), closeTo(0.35, 1e-9));
    });

    test('les valeurs hors bornes sont ramenées à l\'écriture', () async {
      const store = SharedPreferencesVolumeStore();
      await store.write(3);
      expect(await store.read(), 1);
    });

    // Un fichier de préférences écrit par une autre version, ou trafiqué :
    // `setVolume` refuserait la valeur, l'application ne doit pas démarrer sur
    // une exception pour autant.
    test(
      'une valeur hors bornes déjà stockée est ramenée à la lecture',
      () async {
        SharedPreferences.setMockInitialValues({'playback_volume': 42.0});
        expect(await const SharedPreferencesVolumeStore().read(), 1);
      },
    );
  });

  group('InMemoryVolumeStore', () {
    test('part vide, garde ce qu\'on lui donne, borne les valeurs', () async {
      final store = InMemoryVolumeStore();
      expect(await store.read(), isNull);

      await store.write(0.5);
      expect(await store.read(), 0.5);

      await store.write(-1);
      expect(await store.read(), 0);
    });

    test('accepte une valeur initiale', () async {
      expect(await InMemoryVolumeStore(0.25).read(), 0.25);
    });
  });
}
