import 'dart:typed_data';

/// Source audio injectable, indépendante des canaux de plateforme de `record`.
abstract interface class AudioCapture {
  Future<bool> hasPermission();
  Future<bool> supportsAacAdts();
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> dispose();
}
