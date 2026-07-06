class LiveStream {
  const LiveStream({
    required this.id,
    required this.title,
    required this.startedAt,
    this.description,
    this.category,
    this.listenerCount,
  });

  final String id;
  final String title;
  final DateTime? startedAt;
  final String? description;
  final String? category;
  final int? listenerCount;

  Duration? liveDurationAt(DateTime now) {
    final start = startedAt;
    if (start == null) return null;
    final elapsed = now.difference(start);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }
}
