import 'dart:io' show Platform;

import 'package:permission_handler/permission_handler.dart';

/// Demande la permission notifications (Android 13+) pour que la notification
/// média du service de premier plan (STR-109) — et donc les contrôles écran
/// verrouillé — soient visibles. Sans demande runtime, l'utilisateur ne
/// l'accorde jamais et rien ne s'affiche.
///
/// No-op hors Android : iOS gère le Now Playing sans cette permission, et
/// Android < 13 l'accorde implicitement. Le garde `Platform.isAndroid` évite
/// tout appel de plateforme sur l'hôte de test.
Future<void> ensureNotificationPermission() async {
  if (!Platform.isAndroid) return;
  final status = await Permission.notification.status;
  if (status.isDenied) {
    await Permission.notification.request();
  }
}
