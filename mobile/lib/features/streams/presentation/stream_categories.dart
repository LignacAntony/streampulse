/// Catégories de flux proposées à l'écran Découvrir.
///
/// La **clé** (`key`) est la valeur envoyée au backend : elle doit rester
/// alignée sur la liste blanche `validCategories` du domaine streaming
/// (`backend/internal/streaming/service.go`). Une clé hors liste renvoie 400.
/// Le **libellé** (`label`) est l'affichage français ; il ne circule jamais sur
/// le réseau.
library;

class StreamCategory {
  const StreamCategory({required this.key, required this.label});

  final String key;
  final String label;
}

/// Ordre d'affichage des chips. « Tous » (pas de filtre) est géré à part par
/// l'écran : ici, uniquement les vraies catégories du backend.
const List<StreamCategory> streamCategories = [
  StreamCategory(key: 'music', label: 'Musique'),
  StreamCategory(key: 'talk', label: 'Talk'),
  StreamCategory(key: 'technology', label: 'Tech'),
  StreamCategory(key: 'gaming', label: 'Gaming'),
  StreamCategory(key: 'news', label: 'Actus'),
  StreamCategory(key: 'sport', label: 'Sport'),
  StreamCategory(key: 'other', label: 'Autre'),
];
