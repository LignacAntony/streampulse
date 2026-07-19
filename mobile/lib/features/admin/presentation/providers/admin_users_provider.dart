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
  String _search = '';
  String? _roleFilter;
  String? _statusFilter;

  Timer? _debounce;

  List<AdminUser> get users => _users;
  int get total => _total;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;
  String get search => _search;
  String? get roleFilter => _roleFilter;
  String? get statusFilter => _statusFilter;

  /// Reste des utilisateurs à charger (pagination offset/limit, cf. `loadMore`).
  bool get hasMore => _users.length < _total;

  /// (Re)charge la première page avec les filtres/recherche courants.
  /// `reset: true` (défaut) vide la liste affichée avant le fetch (filtres,
  /// recherche) ; `reset: false` conserve l'ancienne liste pendant le fetch.
  Future<void> load({bool reset = true}) async {
    if (reset) {
      _users = const [];
      _total = 0;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repository.listUsers(
        search: _searchOrNull,
        role: _roleFilter,
        status: _statusFilter,
        limit: pageSize,
        offset: 0,
      );
      _users = result.users;
      _total = result.total;
    } catch (e) {
      _error = _messageFor(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Charge la page suivante (offset = nombre déjà chargé) et l'accumule.
  /// No-op si un chargement est déjà en cours ou si tout est déjà chargé.
  Future<void> loadMore() async {
    if (_loading || _loadingMore || !hasMore) return;
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
      _users = [..._users, ...result.users];
      _total = result.total;
      _error = null;
    } catch (e) {
      _error = _messageFor(e);
    } finally {
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
  Future<void> toggleActive(AdminUser user) async {
    final updated = await _repository.setUserActive(user.id, !user.isActive);
    final index = _users.indexWhere((u) => u.id == user.id);
    if (index != -1) {
      _users = List.of(_users)..[index] = updated;
      notifyListeners();
    }
  }

  /// Supprime [user] et le retire de la liste locale après succès. Les
  /// erreurs (409 self-action / dernier admin) sont relayées à l'appelant.
  Future<void> delete(AdminUser user) async {
    await _repository.deleteUser(user.id);
    _users = _users.where((u) => u.id != user.id).toList();
    if (_total > 0) _total -= 1;
    notifyListeners();
  }

  String? get _searchOrNull => _search.isEmpty ? null : _search;

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
