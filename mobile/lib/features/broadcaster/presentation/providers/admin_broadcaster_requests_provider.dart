import 'package:flutter/foundation.dart';

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/admin_broadcaster_request.dart';
import '../../domain/repositories/admin_broadcaster_repository.dart';

/// Pilote `AdminBroadcasterRequestsScreen` : liste des demandes de rôle
/// diffuseur avec filtre par statut, approbation et refus.
///
/// La liste backend n'est pas paginée (volume faible) : pas de `loadMore`.
/// `approve`/`reject` ne capturent PAS l'erreur — elles la relaient à l'écran
/// pour un toast (409 « déjà traitée ») — puis un `load()` rafraîchit l'état
/// réel, comme `PlaylistsController`. Seul `load` expose `error` en état.
class AdminBroadcasterRequestsProvider extends ChangeNotifier {
  AdminBroadcasterRequestsProvider(this._repository);

  final AdminBroadcasterRepository _repository;

  List<AdminBroadcasterRequest> _requests = const [];
  bool _loading = false;
  String? _error;
  bool _isNetworkError = false;

  /// Filtre courant : `null` = tous, sinon `pending`/`approved`/`rejected`.
  /// Défaut `pending` : c'est ce qui appelle une action de l'admin.
  String? _statusFilter = 'pending';

  bool _disposed = false;

  List<AdminBroadcasterRequest> get requests => _requests;
  bool get loading => _loading;
  String? get error => _error;
  bool get isNetworkError => _isNetworkError;
  String? get statusFilter => _statusFilter;

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// (Re)charge la liste avec le filtre courant. Réentrant : seule la réponse
  /// du chargement le plus récent écrit l'état (garde de génération).
  Future<void> load() async {
    final gen = ++_loadGeneration;
    _loading = true;
    _clearError();
    _notify();
    try {
      final result = await _repository.list(status: _statusFilter);
      if (gen != _loadGeneration) return;
      _requests = result;
    } catch (e) {
      if (gen != _loadGeneration) return;
      _setError(e);
    } finally {
      if (gen == _loadGeneration) {
        _loading = false;
        _notify();
      }
    }
  }

  int _loadGeneration = 0;

  Future<void> setStatusFilter(String? status) {
    if (_statusFilter == status) return Future.value();
    _statusFilter = status;
    return load();
  }

  /// Approuve [request] puis recharge : la demande traitée quitte le filtre
  /// « pending ». Relaie l'exception à l'appelant (toast).
  Future<void> approve(AdminBroadcasterRequest request, {String? note}) async {
    try {
      await _repository.approve(request.id, note: note);
    } finally {
      await load();
    }
  }

  Future<void> reject(AdminBroadcasterRequest request, {String? note}) async {
    try {
      await _repository.reject(request.id, note: note);
    } finally {
      await load();
    }
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
    return 'Impossible de charger les demandes';
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
