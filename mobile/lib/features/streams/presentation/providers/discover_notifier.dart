import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../tracks/domain/entities/public_track.dart';
import '../../../tracks/domain/repositories/track_repository.dart';
import '../../domain/entities/live_stream.dart';
import '../../domain/repositories/stream_repository.dart';

class DiscoverNotifier extends ChangeNotifier {
  DiscoverNotifier(this._repository, this._trackRepository);

  final StreamRepository _repository;
  final TrackRepository _trackRepository;

  static const int pageSize = 50;

  /// Délai avant de lancer une recherche : on attend que l'auditeur ait fini de
  /// taper plutôt que d'interroger l'API à chaque frappe.
  static const Duration _searchDebounce = Duration(milliseconds: 350);

  List<LiveStream> _streams = const [];
  List<PublicTrack> _publicTracks = const [];
  bool _isLoading = false;
  bool _hasError = false;

  /// Catégorie sélectionnée (clé backend), `null` = « Tous ».
  String? _category;

  /// Terme de recherche courant (déjà trimé).
  String _search = '';

  Timer? _debounce;

  /// Numéro de chargement courant : un `load()` plus récent invalide les
  /// réponses d'un précédent encore en vol (l'auditeur a changé de filtre
  /// entre-temps), sinon la liste pourrait « revenir en arrière ».
  int _generation = 0;

  List<LiveStream> get streams => _streams;
  List<PublicTrack> get publicTracks => _publicTracks;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String? get selectedCategory => _category;
  String get searchQuery => _search;

  /// Un filtre (catégorie ou recherche) est-il actif ? Les pistes publiques ne
  /// sont montrées que dans la vue de découverte libre : leur endpoint ne
  /// connaît ni catégorie ni recherche, les afficher pendant un filtre laisserait
  /// croire qu'elles y échappent.
  bool get isFiltering => _category != null || _search.isNotEmpty;

  bool get isEmpty =>
      !_isLoading && !_hasError && _streams.isEmpty && _publicTracks.isEmpty;

  /// Sélectionne une catégorie (`null` = « Tous ») et recharge immédiatement.
  Future<void> selectCategory(String? category) {
    if (_category == category) return Future.value();
    _category = category;
    notifyListeners();
    return load();
  }

  /// À brancher sur `onChanged` du champ de recherche : débounce puis recharge.
  void onSearchChanged(String value) {
    final trimmed = value.trim();
    if (trimmed == _search) return;
    _search = trimmed;
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, load);
  }

  Future<void> load() async {
    final generation = ++_generation;
    _debounce?.cancel();
    _isLoading = true;
    _hasError = false;
    notifyListeners();

    var streamsFailed = false;
    var tracksFailed = false;

    List<LiveStream> streams = const [];
    try {
      streams = await _repository.listLiveStreams(
        limit: pageSize,
        category: _category,
        search: _search,
      );
    } catch (_) {
      streamsFailed = true;
    }

    // Pistes publiques : seulement en découverte libre (leur API n'a pas de
    // filtre), et inutile de les recharger si un filtre est actif.
    List<PublicTrack> tracks = const [];
    if (!isFiltering) {
      try {
        tracks = await _trackRepository.listPublicTracks(limit: pageSize);
      } catch (_) {
        tracksFailed = true;
      }
    }

    // Une réponse périmée (l'auditeur a changé de filtre entre-temps) est jetée.
    if (generation != _generation) return;

    _streams = streams;
    _publicTracks = tracks;
    // En vue filtrée, seuls les flux comptent : l'échec du chargement des pistes
    // n'y est pas une erreur puisqu'on ne les demande pas.
    _hasError = isFiltering ? streamsFailed : (streamsFailed && tracksFailed);
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
