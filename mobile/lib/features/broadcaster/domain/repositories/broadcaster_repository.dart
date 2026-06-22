import '../entities/broadcaster_request.dart';

abstract class BroadcasterRepository {
  Future<BroadcasterRequest> requestBroadcaster({String message});

  /// `null` si l'utilisateur n'a jamais soumis de demande (404 backend).
  Future<BroadcasterRequest?> getMyRequest();
}
