import 'package:flutter/foundation.dart';

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/admin_broadcaster_request.dart';
import '../../domain/entities/broadcaster_request.dart';
import '../../domain/repositories/admin_broadcaster_repository.dart';

/// Pilote `AdminBroadcasterRequestsScreen` : liste des demandes de rôle
/// diffuseur avec filtre par statut, approbation et refus.
///
/// La liste backend n'est pas paginée (volume faible) : pas de `loadMore`.
///
/// `approve`/`reject` **ne rechargent pas** la liste : sur succès, l'état local
/// est mis à jour (statut de la demande) puis la demande est retirée si elle ne
/// correspond plus au filtre courant. Un `finally { load() }` masquait un
/// succès partiel — la mutation réussie côté serveur mais le rechargement
/// échouant sur une coupure réseau : `load()` avale son erreur, l'appelant ne
/// voyait rien et affichait « approuvé » sur une carte restée « en attente ».
/// La mise à jour locale reflète la réussite sans dépendre d'un second
/// aller-retour réseau. Les erreurs de mutation sont relayées à l'écran (toast).
class AdminBroadcasterRequestsProvider extends ChangeNotifier {
  AdminBroadcasterRequestsProvider(this._repository);

  final AdminBroadcasterRepository _repository;

  List<AdminBroadcasterRequest> _requests = const [];
  bool _loading = false;
  String? _error;
  bool _isNetworkError = false;

  /// Filtre courant : `null` = toutes. Typé avec l'enum domaine (plus de chaîne
  /// magique à faire coïncider à la main avec le serveur et l'enum).
  /// Défaut « en attente » : c'est ce qui appelle une action de l'admin.
  BroadcasterRequestStatus? _statusFilter = BroadcasterRequestStatus.pending;

  /// Ids des demandes dont une mutation (approve/reject) est en vol : garde
  /// anti-double-envoi (l'écran désactive les actions de la carte concernée).
  final Set<String> _mutating = <String>{};

  bool _disposed = false;

  List<AdminBroadcasterRequest> get requests => _requests;
  bool get loading => _loading;
  String? get error => _error;
  bool get isNetworkError => _isNetworkError;
  BroadcasterRequestStatus? get statusFilter => _statusFilter;

  /// Vrai si une mutation est en cours sur cette demande (bouton à neutraliser).
  bool isMutating(String id) => _mutating.contains(id);

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

  Future<void> setStatusFilter(BroadcasterRequestStatus? status) {
    if (_statusFilter == status) return Future.value();
    _statusFilter = status;
    return load();
  }

  /// Approuve [request]. No-op si une mutation est déjà en vol sur cette
  /// demande (anti-double-envoi). Relaie l'exception à l'appelant (toast).
  Future<void> approve(AdminBroadcasterRequest request, {String? note}) =>
      _mutate(
        request,
        note: note,
        newStatus: BroadcasterRequestStatus.approved,
        call: (id, n) => _repository.approve(id, note: n),
      );

  Future<void> reject(AdminBroadcasterRequest request, {String? note}) =>
      _mutate(
        request,
        note: note,
        newStatus: BroadcasterRequestStatus.rejected,
        call: (id, n) => _repository.reject(id, note: n),
      );

  Future<void> _mutate(
    AdminBroadcasterRequest request, {
    required String? note,
    required BroadcasterRequestStatus newStatus,
    required Future<void> Function(String id, String? note) call,
  }) async {
    if (_mutating.contains(request.id)) return;
    _mutating.add(request.id);
    _notify();
    try {
      await call(request.id, note);
      _applyLocalStatus(request.id, newStatus);
    } finally {
      _mutating.remove(request.id);
      _notify();
    }
  }

  /// Reflète localement le nouveau statut d'une demande traitée : met à jour la
  /// carte, puis la retire si elle ne correspond plus au filtre actif (ex.
  /// filtre « en attente » après approbation). Évite un rechargement réseau.
  void _applyLocalStatus(String id, BroadcasterRequestStatus status) {
    _requests = _requests
        .map((r) => r.id == id ? r.copyWith(status: status) : r)
        .where((r) => _statusFilter == null || r.status == _statusFilter)
        .toList();
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
