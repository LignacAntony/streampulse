import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'connectivity_service.dart';

class ConnectivityServiceImpl extends ConnectivityService {
  ConnectivityServiceImpl() {
    _subscription = Connectivity().onConnectivityChanged.listen(_onChanged);
    _init();
  }

  bool _online = true;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final _controller = StreamController<bool>.broadcast();

  Future<void> _init() async {
    final results = await Connectivity().checkConnectivity();
    _update(_hasConnection(results));
  }

  void _onChanged(List<ConnectivityResult> results) {
    _update(_hasConnection(results));
  }

  bool _hasConnection(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  void _update(bool online) {
    if (_online == online) return;
    _online = online;
    _controller.add(online);
    notifyListeners();
  }

  @override
  bool get isOnline => _online;

  @override
  Stream<bool> get onlineStream => _controller.stream;

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.close();
    super.dispose();
  }
}
