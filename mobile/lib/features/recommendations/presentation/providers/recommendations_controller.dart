import 'package:flutter/foundation.dart';

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/recommended_track.dart';
import '../../domain/repositories/recommendation_repository.dart';

/// Pilote la section « Pour toi » (US-09-04) : charge les pistes recommandées au
/// demandeur d'après son historique d'écoute.
///
/// Non optimiste, un seul chargement : `load`/`refresh` appellent le repository
/// et exposent `error`/`isNetworkError` en état. La section est masquée quand la
/// liste est vide (aucune piste dans la bibliothèque) : on ne montre pas une
/// section « Pour toi » sans contenu.
class RecommendationsController extends ChangeNotifier {
  RecommendationsController(this._repository);

  final RecommendationRepository _repository;

  List<RecommendedTrack> _items = const [];
  bool _loading = false;
  String? _error;
  bool _isNetworkError = false;

  List<RecommendedTrack> get items => _items;
  bool get loading => _loading;
  String? get error => _error;
  bool get isNetworkError => _isNetworkError;
  bool get hasItems => _items.isNotEmpty;

  Future<void> load() async {
    _loading = true;
    _error = null;
    _isNetworkError = false;
    notifyListeners();
    try {
      _items = await _repository.fetch();
    } catch (e) {
      _error = e is NetworkException
          ? 'Pas de connexion réseau'
          : 'Impossible de charger les recommandations';
      _isNetworkError = e is NetworkException;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();
}
