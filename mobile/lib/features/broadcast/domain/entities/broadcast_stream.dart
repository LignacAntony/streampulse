/// Un flux vu par son **propriétaire** (tableau de bord diffuseur, US-06-01).
///
/// Distinct de `LiveStream` (feature `streams`), qui est la vue auditeur : ce
/// type porte en plus [streamKey] et [streamSourceUrl], deux secrets qui ne
/// doivent jamais transiter par le chemin auditeur (découverte, favoris,
/// lecteur). La séparation est structurelle et volontaire — cf. ADR 024.
class BroadcastStream {
  const BroadcastStream({
    required this.id,
    required this.title,
    required this.status,
    required this.isPublic,
    this.description,
    this.category,
    this.startedAt,
    this.streamKey,
    this.streamSourceUrl,
  });

  final String id;
  final String title;

  /// Statut du flux : `idle`, `live` ou `ended`.
  final String status;
  final bool isPublic;
  final String? description;

  /// Catégorie parmi [kStreamCategories], ou null si non renseignée.
  final String? category;

  /// Début du direct courant ; null tant que le flux n'a jamais été démarré.
  final DateTime? startedAt;

  /// Secret d'ingest. Non nul uniquement parce que le propriétaire est le seul
  /// destinataire de cette entité — à ne jamais logger ni afficher en clair
  /// sans action explicite de l'utilisateur.
  final String? streamKey;

  /// URL complète de push, `{base}/api/streams/ingest/{streamKey}` — contient
  /// donc le secret. Mêmes précautions que [streamKey].
  final String? streamSourceUrl;

  bool get isLive => status == 'live';
  bool get isIdle => status == 'idle';
  bool get isEnded => status == 'ended';

  /// Durée écoulée depuis le début du direct, ou null si le flux n'est pas en
  /// direct. Bornée à zéro : une horloge client en avance sur le serveur ne
  /// doit pas produire de durée négative.
  Duration? liveDurationAt(DateTime now) {
    final start = startedAt;
    if (!isLive || start == null) return null;
    final elapsed = now.difference(start);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  BroadcastStream copyWith({
    String? status,
    DateTime? startedAt,
    bool clearStartedAt = false,
  }) {
    return BroadcastStream(
      id: id,
      title: title,
      status: status ?? this.status,
      isPublic: isPublic,
      description: description,
      category: category,
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
      streamKey: streamKey,
      streamSourceUrl: streamSourceUrl,
    );
  }
}

/// Liste blanche des catégories, miroir de `validCategories` côté backend
/// (`internal/streaming/service.go`). Toute valeur hors de cette liste est
/// rejetée en 400 par l'API : la garder ici évite un aller-retour inutile et
/// permet de piloter le sélecteur du formulaire de création.
const List<String> kStreamCategories = [
  'music',
  'talk',
  'technology',
  'gaming',
  'news',
  'sport',
  'other',
];

/// Bornes de validation reprises du backend (`MinTitleLen`/`MaxTitleLen`,
/// `MaxDescriptionLen`) pour valider côté client avant l'appel.
const int kStreamTitleMinLength = 3;
const int kStreamTitleMaxLength = 120;
const int kStreamDescriptionMaxLength = 500;
