import 'playback_order.dart';
import 'playback_transport.dart';

export 'playback_order.dart' show PlaybackOrder, QueueRepeatMode;
export 'playback_transport.dart' show PlaybackStatus, PlaybackTransport;

/// Une entrée de la file d'attente, telle que le lecteur natif la consomme :
/// une URL à jouer et de quoi renseigner la notification / l'écran verrouillé.
///
/// Volontairement sans lien avec l'entité `PlaylistTrack` du domaine : le noyau
/// audio ne connaît pas les playlists, il enchaîne des URLs (une file de pistes
/// aujourd'hui, autre chose demain).
class QueueItem {
  const QueueItem({
    required this.id,
    required this.url,
    required this.title,
    this.artist,
    this.duration,
  });

  final String id;
  final String url;
  final String title;
  final String? artist;

  /// Durée connue de la piste, si le client l'a fournie à l'upload. `null` ne
  /// bloque rien : le lecteur natif la découvre en ouvrant le fichier, elle sert
  /// seulement à afficher la barre de progression système sans attendre.
  final Duration? duration;
}

/// Service de lecture **d'une file d'attente** (US-05-04), partagé au niveau
/// application comme [AudioPlaybackService] et servi par le même lecteur natif :
/// démarrer une file remplace donc le direct en cours, et réciproquement.
///
/// L'enchaînement automatique d'une piste à la suivante est assuré par le
/// lecteur natif (aucune minuterie applicative à surveiller) ; le contrôleur se
/// contente de suivre [currentIndexStream] pour savoir où en est la file.
abstract class QueuePlaybackService implements PlaybackTransport {
  /// Index de la piste en cours dans la file, ou `null` si aucune file n'est
  /// chargée. Émet à chaque passage automatique comme à chaque saut manuel.
  Stream<int?> get currentIndexStream;

  /// Position dans la piste en cours. Relevée avant une reprise après erreur
  /// pour repartir d'où l'auditeur en était, plutôt que du début de la piste.
  Duration get position;

  /// Ordre dans lequel le lecteur enchaînera la file chargée (US-05-05) :
  /// identité en lecture normale, permutation en lecture aléatoire.
  ///
  /// Lu **après** [loadQueue] / [setShuffleEnabled], jamais deviné : c'est le
  /// lecteur natif qui tire le mélange, et l'afficher depuis une autre source
  /// mentirait sur ce qui va réellement jouer.
  PlaybackOrder get playbackOrder;

  /// Active ou coupe la lecture aléatoire. À l'activation, un nouvel ordre est
  /// tiré en **gardant la piste courante en tête** : basculer en aléatoire ne
  /// coupe jamais ce qu'on est en train d'écouter.
  Future<void> setShuffleEnabled(bool enabled);

  /// Règle la répétition. Elle gouverne l'**enchaînement automatique** ; les
  /// sauts manuels suivent [PlaybackOrder.relative] (cf. `QueueRepeatMode.one`).
  ///
  /// `setRepeat` et non `setRepeatMode` : ce dernier nom est déjà celui de la
  /// commande système d'`audio_service`, que l'implémentation hérite.
  Future<void> setRepeat(QueueRepeatMode mode);

  /// Charge [items] et positionne la lecture sur [initialIndex], à
  /// [initialPosition] dans cette piste. Ne démarre pas la lecture (le
  /// contrôleur enchaîne), pour la même raison que `loadUri`.
  ///
  /// [headers] est envoyé avec **chaque** requête de piste : les fichiers audio
  /// d'une bibliothèque sont privés, le lecteur natif doit s'authentifier.
  ///
  /// [order] réapplique un ordre de lecture existant au lieu d'en faire tirer un
  /// neuf. Sert aux rechargements **subis** (reprise après erreur) : sans lui,
  /// une coupure réseau réécrirait la suite de la file alors que l'auditeur n'a
  /// rien demandé. `null` = nouveau tirage si l'aléatoire est actif.
  Future<void> loadQueue(
    List<QueueItem> items, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    Map<String, String> headers = const {},
    PlaybackOrder? order,
  });

  /// Saute à la piste [index] de la file et repart de son début.
  Future<void> skipToIndex(int index);
}
