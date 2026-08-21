import 'dart:math';

/// Génère l'en-tête `traceparent` du standard W3C Trace Context (STR-244,
/// ADR 041).
///
/// Sans lui, une trace commence au serveur : Tempo montre le trajet de l'API
/// jusqu'à PostgreSQL, mais rien de ce que l'utilisateur a réellement attendu —
/// résolution DNS, poignée de main, latence radio. Émettre un identifiant depuis
/// le client rattache la trace serveur à la requête mobile qui l'a causée.
///
/// Le backend accepte déjà l'en-tête : son propagateur est `TraceContext` et son
/// échantillonneur `ParentBased(AlwaysSample)` (`observability/tracer.go`). Il
/// ne manquait que l'émetteur.
///
/// Objet **pur**, sans dépendance à Dio ni à Flutter, comme `InterruptionPolicy`
/// et `PlaybackOrder` : la génération d'identifiants se teste sans réseau.
class TraceContext {
  TraceContext({Random? random, this.sampled = defaultSampled})
    : _random = random ?? Random.secure();

  /// Nom de l'en-tête, tel que défini par le standard (minuscules imposées).
  static const String header = 'traceparent';

  /// Version du format. `00` est la seule publiée à ce jour ; un serveur qui en
  /// verrait une autre doit tenter de la lire quand même.
  static const String version = '00';

  /// Échantillonnage par défaut. `true` marque **toutes** les requêtes mobiles
  /// comme à conserver : le backend suit le drapeau du parent, donc c'est ce
  /// réglage qui rend une trace mobile visible dans Tempo.
  ///
  /// Assumé pour ce projet — le volume est celui d'une démonstration, et une
  /// trace échantillonnée au hasard est inexploitable quand on cherche
  /// précisément la requête qu'on vient de faire. Réductible sans recompiler la
  /// logique : `--dart-define=TRACE_SAMPLED=false`.
  static const bool defaultSampled = bool.fromEnvironment(
    'TRACE_SAMPLED',
    defaultValue: true,
  );

  static const int _zeroCodeUnit = 0x30; // '0'

  final Random _random;

  /// Si les requêtes demandent au serveur de conserver la trace.
  final bool sampled;

  /// Construit une valeur `traceparent` neuve : `00-<trace 32 hex>-<span 16 hex>-<flags>`.
  ///
  /// Un identifiant par requête, sans état conservé entre les appels : le client
  /// n'a pas de notion de trace en cours à laquelle se rattacher. Chaque requête
  /// est donc la racine de sa propre trace, et le serveur y greffe ses spans.
  String newTraceparent() {
    final flags = sampled ? '01' : '00';
    return '$version-${_hex(16)}-${_hex(8)}-$flags';
  }

  /// Génère [byteCount] octets aléatoires en hexadécimal minuscule.
  ///
  /// Le standard interdit un identifiant entièrement nul : la boucle retire ce
  /// cas plutôt que de le corriger octet par octet, ce qui biaiserait la
  /// distribution. La probabilité de le tirer est de 2^-128.
  String _hex(int byteCount) {
    String candidate;
    do {
      final buffer = StringBuffer();
      for (var i = 0; i < byteCount; i++) {
        buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
      }
      candidate = buffer.toString();
    } while (candidate.codeUnits.every((unit) => unit == _zeroCodeUnit));
    return candidate;
  }
}
