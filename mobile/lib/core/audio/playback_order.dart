/// Mode de répétition d'une file d'attente (US-05-05).
///
/// Vocabulaire applicatif volontairement distinct du `LoopMode` de just_audio :
/// seul le handler traduit l'un vers l'autre, le reste de l'application (et ses
/// tests) n'a pas à dépendre du lecteur natif.
///
/// Préfixé `Queue` parce que `material.dart` exporte déjà un `RepeatMode`
/// (animations) : sans ça, tout widget qui affiche le mode devrait renommer
/// l'un des deux à l'import.
enum QueueRepeatMode {
  /// La file s'arrête après la dernière piste.
  off,

  /// La piste courante se répète indéfiniment.
  one,

  /// La file reboucle sur sa première piste après la dernière.
  all,
}

/// Ordre de lecture effectif d'une file : la liste des index de la file
/// d'origine, dans l'ordre où le lecteur les enchaînera. Identité en lecture
/// normale, permutation en lecture aléatoire.
///
/// Objet **pur et testable** (même parti pris qu'`InterruptionPolicy`,
/// ADR 033) : c'est ici que vit la règle du saut manuel, et elle est appliquée
/// aux deux surfaces qui sautent — les boutons de l'application via le
/// contrôleur, et ceux de la notification via `StreamAudioHandler`. Une seule
/// implémentation, donc aucune divergence possible entre les deux.
class PlaybackOrder {
  const PlaybackOrder(this.indices);

  /// Ordre de lecture vide : aucun saut possible.
  static const PlaybackOrder empty = PlaybackOrder([]);

  /// Ordre naturel de `length` éléments (aucun mélange).
  factory PlaybackOrder.natural(int length) =>
      PlaybackOrder(List.generate(length, (i) => i));

  /// Index de la file d'origine, dans l'ordre de lecture.
  final List<int> indices;

  bool get isEmpty => indices.isEmpty;

  /// Rang de [index] dans l'ordre de lecture (« piste 3 sur 12 » compte les
  /// pistes telles qu'elles seront jouées, pas telles qu'elles sont rangées).
  /// `-1` si la piste n'appartient pas à cet ordre.
  int positionOf(int index) => indices.indexOf(index);

  /// Index de la file à jouer [offset] rangs après [current] dans l'ordre de
  /// lecture, ou `null` s'il n'y en a pas.
  ///
  /// [wrap] (mode `all`) fait reboucler aux deux extrémités.
  ///
  /// **`QueueRepeatMode.one` n'intervient pas ici** : il ne gouverne que
  /// l'enchaînement automatique, pas les boutons précédent/suivant. C'est le
  /// seul écart assumé avec just_audio, dont `seekToNext` rejoue la piste
  /// courante quand `LoopMode.one` est actif — un bouton « suivant » qui ne
  /// change pas de piste passerait pour une panne.
  int? relative(int current, int offset, {required bool wrap}) {
    if (indices.isEmpty) return null;
    final position = positionOf(current);
    if (position < 0) return null;

    var target = position + offset;
    if (target < 0 || target >= indices.length) {
      if (!wrap) return null;
      // L'opérateur `%` de Dart rend toujours un reste positif : -1 sur une
      // file de 3 donne bien 2 (la dernière piste), sans cas particulier.
      target %= indices.length;
    }
    return indices[target];
  }
}
