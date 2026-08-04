/// Une tentative HTTP. Sa durée est celle de la requête chunked entière.
abstract interface class AudioIngestClient {
  Future<void> push(Uri sourceUrl, Stream<List<int>> audio);
  Future<void> cancel();
}
