import 'package:flutter/foundation.dart';

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/admin_stream.dart';
import '../../domain/repositories/admin_streams_repository.dart';

/// Pilote `AdminStreamsScreen` : liste paginée des flux en direct (admin) et
/// interruption forcée d'un flux.
///
/// Même mécanique anti-staleness que `AdminUsersProvider` (cf. sa
/// documentation pour le détail complet du raisonnement) : deux compteurs
/// distincts, `_loadGeneration` (arbitrage load-vs-load) et `_listVersion`
/// (protection de `loadMore` contre une mutation concurrente de `_streams`).
///
/// `stop` ne capture PAS les erreurs : elles sont relayées à l'appelant
/// (l'écran) pour afficher un toast avec le message serveur en cas de 409 —
/// seuls `load`/`loadMore` exposent `error` en état, car ce sont les seules
/// méthodes sans point d'appel unique à côté duquel afficher un toast.
class AdminStreamsProvider extends ChangeNotifier {
  AdminStreamsProvider(this._repository);

  final AdminStreamsRepository _repository;

  static const int pageSize = 20;

  List<AdminStream> _streams = const [];
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  bool _isNetworkError = false;

  /// Jeton de génération anti out-of-order : incrémenté UNIQUEMENT par
  /// `load()`. Une réponse `load`/`loadMore` (succès OU échec) dont le jeton
  /// capturé ne correspond plus au jeton courant signale qu'un chargement
  /// plus récent est parti entre-temps (pull-to-refresh répété) — et elle
  /// est ignorée au lieu d'écraser l'état le plus récent.
  ///
  /// Ne PAS le faire avancer depuis `stop` (cf. `_listVersion` ci-dessous) :
  /// le `finally` de `load()` ne remet `_loading` à faux QUE si
  /// `gen == _loadGeneration` (invariant load-vs-load uniquement) — une
  /// mutation qui avancerait ce jeton pendant qu'un `load()` est en vol lui
  /// ferait croire qu'un chargement plus récent l'a remplacé, et son
  /// `finally` ne réinitialiserait plus jamais `_loading` (spinner figé,
  /// silencieusement, jusqu'au prochain `load()` qui réussit sans
  /// concurrence — régression détectée en revue sur `AdminUsersProvider`,
  /// cf. test « pas de spinner figé »).
  int _loadGeneration = 0;

  /// Compteur de version de la liste locale : incrémenté après chaque `stop`
  /// réussi (mutation de `_streams`/`_total`). Sert UNIQUEMENT à `loadMore`,
  /// en complément de `_loadGeneration` : une page déjà en vol au moment d'un
  /// `stop` a capturé un offset (`_streams.length`) et une base
  /// d'accumulation (`[..._streams, ...]`) qui deviennent invalides dès que
  /// `_streams` change sous ses pieds (ligne retirée) — sans ce compteur, la
  /// page obsolète ressusciterait le flux interrompu et désynchroniserait
  /// `_total`. Volontairement séparé de `_loadGeneration` : un `load()`
  /// recharge tout depuis zéro et n'a rien à protéger contre une mutation
  /// concurrente, il ne doit donc PAS être invalidé par elle (contrairement à
  /// `loadMore`).
  int _listVersion = 0;

  List<AdminStream> get streams => _streams;
  int get total => _total;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;

  /// Vrai si [error] provient d'une [NetworkException] (pas de connexion) —
  /// permet à l'écran de choisir une icône adaptée (réseau vs serveur/autre)
  /// sans dupliquer la logique de classification des exceptions.
  bool get isNetworkError => _isNetworkError;

  /// Reste des flux à charger (pagination offset/limit, cf. `loadMore`).
  bool get hasMore => _streams.length < _total;

  /// (Re)charge la première page des flux en direct.
  /// `reset: true` (défaut) vide la liste affichée avant le fetch ;
  /// `reset: false` conserve l'ancienne liste pendant le fetch.
  ///
  /// Réentrant : si un autre `load()` part avant que celui-ci ne réponde
  /// (ex. double pull-to-refresh), seul le PLUS RÉCENT écrit l'état — la
  /// réponse la plus ancienne est jetée, même si elle arrive en dernier.
  Future<void> load({bool reset = true}) async {
    final gen = ++_loadGeneration;
    if (reset) {
      _streams = const [];
      _total = 0;
    }
    _loading = true;
    _clearError();
    notifyListeners();
    try {
      final result = await _repository.listLiveStreams(
        limit: pageSize,
        offset: 0,
      );
      if (gen != _loadGeneration) return; // résultat obsolète : ignoré
      _streams = result.streams;
      _total = result.total;
    } catch (e) {
      if (gen != _loadGeneration) return; // échec obsolète : ignoré aussi
      _setError(e);
    } finally {
      // Un load obsolète ne touche pas à `_loading` : le flag appartient au
      // load le plus récent, qui le remettra à faux dans son propre finally.
      if (gen == _loadGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Charge la page suivante (offset = nombre déjà chargé) et l'accumule.
  /// No-op si un chargement est déjà en cours ou si tout est déjà chargé.
  /// Capture les DEUX compteurs : si un `load()` (pull-to-refresh) part
  /// pendant le vol (`_loadGeneration`), OU si `stop` mute `_streams` pendant
  /// le vol (`_listVersion`), l'offset/l'accumulation capturés ne sont plus
  /// valides et la page obsolète n'est pas appliquée.
  Future<void> loadMore() async {
    if (_loading || _loadingMore || !hasMore) return;
    final gen = _loadGeneration;
    final listVersion = _listVersion;
    _loadingMore = true;
    notifyListeners();
    try {
      final result = await _repository.listLiveStreams(
        limit: pageSize,
        offset: _streams.length,
      );
      // Obsolète si un load() est passé entre-temps OU si `stop` a changé
      // `_streams` sous le vol de cette page.
      if (gen != _loadGeneration || listVersion != _listVersion) return;
      _streams = [..._streams, ...result.streams];
      _total = result.total;
      _clearError();
    } catch (e) {
      if (gen != _loadGeneration || listVersion != _listVersion) return;
      _setError(e);
    } finally {
      // Contrairement à `_loading`, `_loadingMore` n'appartient qu'à CE
      // loadMore : toujours le réinitialiser, même sur résultat obsolète,
      // sinon la pagination resterait bloquée (garde d'entrée ci-dessus).
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// Pull-to-refresh (`RefreshIndicator`) : recharge la première page depuis
  /// le début.
  Future<void> refresh() => load(reset: true);

  /// Arrête de force [stream] ; ne met à jour la liste locale qu'après succès
  /// (pas d'optimistic update). Les erreurs (409, réseau) sont relayées à
  /// l'appelant.
  ///
  /// Retourne `false` en no-op silencieux si [stream] n'est déjà plus dans
  /// `_streams` (retiré entre-temps, ex. déjà arrêté par un autre admin) : le
  /// backend a bien confirmé la mutation, mais il n'y a rien à mettre à jour
  /// localement. L'appelant (l'écran) s'appuie sur ce retour pour ne pas
  /// afficher de toast succès sur un no-op. Retourne `true` si la liste a
  /// bien été mise à jour, auquel cas `_listVersion` est avancé pour
  /// invalider tout `loadMore` en vol désormais obsolète (PAS `load` : cf.
  /// doc de `_loadGeneration`/`_listVersion`).
  Future<bool> stop(AdminStream stream) async {
    await _repository.stopStream(stream.id);
    final index = _streams.indexWhere((s) => s.id == stream.id);
    if (index == -1) return false;
    _streams = _streams.where((s) => s.id != stream.id).toList();
    if (_total > 0) _total -= 1;
    _listVersion++;
    notifyListeners();
    return true;
  }

  void _setError(Object error) {
    _error = _messageFor(error);
    _isNetworkError = error is NetworkException;
  }

  void _clearError() {
    _error = null;
    _isNetworkError = false;
  }

  String _messageFor(Object error) {
    if (error is NetworkException) return 'Pas de connexion réseau';
    return 'Impossible de charger les flux';
  }
}
