/// Une tentative HTTP. Sa durée est celle de la requête chunked entière.
abstract interface class AudioIngestClient {
  Future<void> push(Uri sourceUrl, Stream<List<int>> audio);
  Future<void> cancel();
}

/// Le serveur refuse le push parce qu'une **autre source alimente déjà** ce
/// direct (409 `ingest already in progress`).
///
/// Distincte d'un échec réseau, et c'est tout l'intérêt : la reprise doit
/// s'arrêter net au lieu de réessayer. Un encodeur externe (OBS) peut très bien
/// pousser sur la même clé ; insister aboutirait, après épuisement des
/// tentatives, à un `failed` qui **terminerait le direct de cet encodeur**
/// (ADR 027, invariant « jamais de live silencieux »). Le conflit n'est donc
/// pas une panne : c'est le signal que quelqu'un d'autre fait le travail.
class IngestConflictException implements Exception {
  const IngestConflictException([
    this.message = 'Une autre source alimente déjà ce direct',
  ]);

  final String message;

  @override
  String toString() => 'IngestConflictException: $message';
}
