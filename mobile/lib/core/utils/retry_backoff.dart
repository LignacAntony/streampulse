/// Backoff exponentiel 1, 2, 4… secondes, plafonné sans risque de débordement
/// du décalage binaire lors d'une panne prolongée.
Duration cappedExponentialBackoff(int attempt, {int maxSeconds = 30}) {
  final seconds = attempt >= 5 ? maxSeconds : 1 << attempt;
  return Duration(seconds: seconds > maxSeconds ? maxSeconds : seconds);
}
