import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/admin_user.dart';
import '../../domain/repositories/admin_repository.dart';

/// Pilote `AdminUsersScreen` : liste paginée, recherche (debounce 300 ms),
/// filtres rôle/statut, activation/désactivation et suppression d'un compte.
///
/// `toggleActive`/`delete` ne capturent PAS les erreurs : elles sont relayées
/// à l'appelant (l'écran) pour afficher un toast avec le message serveur en
/// cas de 409 — seul `load`/`loadMore` exposent `error` en état, car ce sont
/// les seules méthodes sans point d'appel unique à côté duquel afficher un toast.
class AdminUsersProvider extends ChangeNotifier {
  AdminUsersProvider(this._repository);

  final AdminRepository _repository;

  static const int pageSize = 20;
  static const Duration searchDebounce = Duration(milliseconds: 300);

  List<AdminUser> _users = const [];
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  bool _isNetworkError = false;
  String _search = '';
  String? _roleFilter;
  String? _statusFilter;

  Timer? _debounce;

  /// Jeton de génération anti out-of-order : incrémenté à chaque `load()`,
  /// et aussi après chaque mutation locale réussie de `_users`/`_total`
  /// (`toggleActive`, `delete`). Une réponse `load`/`loadMore` (succès OU
  /// échec) dont le jeton capturé ne correspond plus au jeton courant est
  /// obsolète — soit un chargement plus récent est parti entre-temps (autre
  /// filtre, autre recherche), soit une mutation a changé `_users` sous ses
  /// pieds — et elle est ignorée au lieu d'écraser l'état le plus récent
  /// (cf. `toggleActive`/`delete` : sans ce bump, une page `loadMore` déjà en
  /// vol au moment d'un `delete` pourrait ressusciter la ligne supprimée et
  /// désynchroniser `_total`).
  int _loadGeneration = 0;

  List<AdminUser> get users => _users;
  int get total => _total;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;

  /// Vrai si [error] provient d'une [NetworkException] (pas de connexion) —
  /// permet à l'écran de choisir une icône adaptée (réseau vs serveur/autre)
  /// sans dupliquer la logique de classification des exceptions.
  bool get isNetworkError => _isNetworkError;
  String get search => _search;
  String? get roleFilter => _roleFilter;
  String? get statusFilter => _statusFilter;

  /// Reste des utilisateurs à charger (pagination offset/limit, cf. `loadMore`).
  bool get hasMore => _users.length < _total;

  /// (Re)charge la première page avec les filtres/recherche courants.
  /// `reset: true` (défaut) vide la liste affichée avant le fetch (filtres,
  /// recherche) ; `reset: false` conserve l'ancienne liste pendant le fetch.
  ///
  /// Réentrant : si un autre `load()` part avant que celui-ci ne réponde
  /// (deux filtres tapés vite), seul le PLUS RÉCENT écrit l'état — la
  /// réponse la plus ancienne est jetée, même si elle arrive en dernier.
  Future<void> load({bool reset = true}) async {
    final gen = ++_loadGeneration;
    if (reset) {
      _users = const [];
      _total = 0;
    }
    _loading = true;
    _clearError();
    notifyListeners();
    try {
      final result = await _repository.listUsers(
        search: _searchOrNull,
        role: _roleFilter,
        status: _statusFilter,
        limit: pageSize,
        offset: 0,
      );
      if (gen != _loadGeneration) return; // résultat obsolète : ignoré
      _users = result.users;
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
  /// Capture le jeton de génération : si un `load()` (filtre, recherche)
  /// part pendant le vol, la page obsolète n'est pas accumulée.
  Future<void> loadMore() async {
    if (_loading || _loadingMore || !hasMore) return;
    final gen = _loadGeneration;
    _loadingMore = true;
    notifyListeners();
    try {
      final result = await _repository.listUsers(
        search: _searchOrNull,
        role: _roleFilter,
        status: _statusFilter,
        limit: pageSize,
        offset: _users.length,
      );
      if (gen != _loadGeneration) return; // un load() est passé entre-temps
      _users = [..._users, ...result.users];
      _total = result.total;
      _clearError();
    } catch (e) {
      if (gen != _loadGeneration) return;
      _setError(e);
    } finally {
      // Contrairement à `_loading`, `_loadingMore` n'appartient qu'à CE
      // loadMore : toujours le réinitialiser, même sur résultat obsolète,
      // sinon la pagination resterait bloquée (garde d'entrée ci-dessus).
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// Met à jour la recherche immédiatement (affichage) et relance `load`
  /// après 300 ms sans nouvelle frappe (debounce), annulant tout timer en attente.
  void setSearch(String value) {
    _search = value;
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(searchDebounce, load);
  }

  Future<void> setRoleFilter(String? role) {
    if (_roleFilter == role) return Future.value();
    _roleFilter = role;
    return load();
  }

  Future<void> setStatusFilter(String? status) {
    if (_statusFilter == status) return Future.value();
    _statusFilter = status;
    return load();
  }

  /// Active/désactive [user] ; ne met à jour la liste locale qu'après succès
  /// (pas d'optimistic update : un 409 — dernier admin, self-action — doit
  /// laisser la liste inchangée). Les erreurs sont relayées à l'appelant.
  ///
  /// Retourne `false` en no-op silencieux si [user] n'est déjà plus dans
  /// `_users` (retiré entre-temps, ex. par un autre admin) : le backend a
  /// bien confirmé la mutation, mais il n'y a rien à mettre à jour
  /// localement. L'appelant (l'écran) s'appuie sur ce retour pour ne pas
  /// afficher de toast succès sur un no-op. Retourne `true` si la liste a
  /// bien été mise à jour, auquel cas le jeton de génération est avancé pour
  /// invalider toute réponse `load`/`loadMore` en vol désormais obsolète.
  Future<bool> toggleActive(AdminUser user) async {
    final updated = await _repository.setUserActive(user.id, !user.isActive);
    final index = _users.indexWhere((u) => u.id == user.id);
    if (index == -1) return false;
    _users = List.of(_users)..[index] = updated;
    _loadGeneration++;
    notifyListeners();
    return true;
  }

  /// Supprime [user] et le retire de la liste locale après succès. Les
  /// erreurs (409 self-action / dernier admin) sont relayées à l'appelant.
  /// Avance le jeton de génération après la mutation locale, pour la même
  /// raison que `toggleActive` (invalider un `loadMore` en vol obsolète).
  Future<void> delete(AdminUser user) async {
    await _repository.deleteUser(user.id);
    _users = _users.where((u) => u.id != user.id).toList();
    if (_total > 0) _total -= 1;
    _loadGeneration++;
    notifyListeners();
  }

  String? get _searchOrNull => _search.isEmpty ? null : _search;

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
    return 'Impossible de charger les utilisateurs';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
