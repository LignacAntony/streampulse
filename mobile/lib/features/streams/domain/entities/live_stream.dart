class LiveStream {
  const LiveStream({
    required this.id,
    required this.title,
    required this.startedAt,
    this.description,
    this.category,
    this.broadcasterName,
    this.listenerCount,
    this.status,
  });

  final String id;
  final String title;
  final DateTime? startedAt;
  final String? description;
  final String? category;

  /// Nom (username) du diffuseur, affiché sous le titre côté auditeur.
  final String? broadcasterName;
  final int? listenerCount;

  /// Statut du flux : 'idle', 'live' ou 'ended' (null si non renseigné).
  final String? status;

  bool get isLive => status == 'live';

  Duration? liveDurationAt(DateTime now) {
    final start = startedAt;
    if (start == null) return null;
    final elapsed = now.difference(start);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }
}
