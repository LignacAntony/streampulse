import 'package:flutter/foundation.dart';

/// État app-level minimal : identifiant du flux que **ce téléphone** diffuse
/// actuellement au micro, ou null.
///
/// Vit hors du dashboard — où `BroadcastNotifier` est scopé — précisément pour
/// être lisible depuis `StreamPlayerScreen`. Sans ce signal, ouvrir son propre
/// live pour voir le chat démarrait la lecture HLS, dont la session audio
/// `playback` interrompt la capture micro : le direct était coupé (le
/// `MicrophoneAudioPublisher` épuisait ses reconnexions puis passait `failed`,
/// et le `BroadcastSessionController` terminait le flux côté serveur). Rejouer
/// son propre direct créait de surcroît une boucle larsen.
///
/// Le lecteur consulte donc cet état : si l'on diffuse ce flux, il n'y touche
/// pas et affiche le chat seul.
class CurrentBroadcast extends ChangeNotifier {
  String? _streamId;

  /// Identifiant du flux diffusé depuis cet appareil, ou null.
  String? get streamId => _streamId;

  /// Vrai si [id] est le flux actuellement diffusé depuis cet appareil.
  bool isBroadcasting(String id) => _streamId == id;

  /// Publie l'identifiant du flux diffusé (ou null à l'arrêt). Idempotent : ne
  /// notifie que sur changement réel, pour ne pas reconstruire inutilement les
  /// écrans qui l'observent.
  void setStreamId(String? id) {
    if (_streamId == id) return;
    _streamId = id;
    notifyListeners();
  }
}
