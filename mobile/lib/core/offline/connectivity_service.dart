import 'dart:async';

import 'package:flutter/foundation.dart';

abstract class ConnectivityService extends ChangeNotifier {
  bool get isOnline;
  Stream<bool> get onlineStream;
}
