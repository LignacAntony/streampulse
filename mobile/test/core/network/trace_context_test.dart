import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/network/trace_context.dart';

/// Random déterministe : la même graine rejoue la même suite d'octets.
Random _seeded() => Random(1234);

/// Random qui ne rend que des zéros — le seul identifiant que le standard
/// W3C interdit.
class _ZeroThenRealRandom implements Random {
  _ZeroThenRealRandom(this._zeroCalls);

  int _zeroCalls;
  final Random _real = Random(7);

  @override
  int nextInt(int max) {
    if (_zeroCalls > 0) {
      _zeroCalls--;
      return 0;
    }
    return _real.nextInt(max);
  }

  @override
  bool nextBool() => _real.nextBool();

  @override
  double nextDouble() => _real.nextDouble();
}

void main() {
  // Le serveur rejette silencieusement un en-tête mal formé : la trace mobile
  // disparaîtrait sans aucune erreur visible, ce qui est le pire des échecs.
  final format = RegExp(r'^00-[0-9a-f]{32}-[0-9a-f]{16}-0[01]$');

  group('TraceContext', () {
    test('produit un traceparent au format W3C', () {
      final value = TraceContext(random: _seeded()).newTraceparent();
      expect(value, matches(format));
    });

    test('tire un identifiant neuf à chaque appel', () {
      final context = TraceContext(random: _seeded());
      final values = List.generate(50, (_) => context.newTraceparent());
      expect(values.toSet().length, 50);
    });

    test('sampled: true marque la trace comme à conserver', () {
      final value = TraceContext(
        random: _seeded(),
        sampled: true,
      ).newTraceparent();
      expect(value, endsWith('-01'));
    });

    // Le backend échantillonne en ParentBased : un drapeau à 00 fait disparaître
    // la trace entière, pas seulement le span client.
    test('sampled: false laisse le serveur écarter la trace', () {
      final value = TraceContext(
        random: _seeded(),
        sampled: false,
      ).newTraceparent();
      expect(value, endsWith('-00'));
    });

    test('ne produit jamais un identifiant entièrement nul', () {
      // 16 octets de trace + 8 de span, tous nuls au premier tirage : les deux
      // identifiants doivent être retirés.
      final value = TraceContext(
        random: _ZeroThenRealRandom(24),
      ).newTraceparent();

      expect(value, matches(format));
      final parts = value.split('-');
      expect(parts[1], isNot('0' * 32));
      expect(parts[2], isNot('0' * 16));
    });

    test('utilise le nom d\'en-tête normalisé', () {
      expect(TraceContext.header, 'traceparent');
    });
  });
}
