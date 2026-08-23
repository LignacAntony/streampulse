import 'package:flutter/foundation.dart';

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/admin_chat_message.dart';
import '../../domain/entities/admin_global_ban.dart';
import '../../domain/repositories/admin_chat_repository.dart';

class AdminUserMessagesProvider extends ChangeNotifier {
  AdminUserMessagesProvider(this._repository, this.userId);

  final AdminChatRepository _repository;
  final String userId;

  static const int pageSize = 20;

  List<AdminChatMessage> _messages = const [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  bool _isNetworkError = false;

  List<AdminChatMessage> get messages => _messages;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  bool get isNetworkError => _isNetworkError;

  Future<void> load() async {
    _loading = true;
    _error = null;
    _isNetworkError = false;
    notifyListeners();
    try {
      final result = await _repository.listUserMessages(
        userId,
        limit: pageSize,
        offset: 0,
      );
      _messages = result;
      _hasMore = result.length >= pageSize;
    } catch (e) {
      _error = _messageFor(e);
      _isNetworkError = e is NetworkException;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    _loadingMore = true;
    notifyListeners();
    try {
      final result = await _repository.listUserMessages(
        userId,
        limit: pageSize,
        offset: _messages.length,
      );
      _messages = [..._messages, ...result];
      _hasMore = result.length >= pageSize;
    } catch (e) {
      _error = _messageFor(e);
      _isNetworkError = e is NetworkException;
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  String _messageFor(Object error) {
    if (error is NetworkException) return 'Pas de connexion réseau';
    return 'Impossible de charger les messages';
  }
}

class AdminGlobalBansProvider extends ChangeNotifier {
  AdminGlobalBansProvider(this._repository);

  final AdminChatRepository _repository;

  List<AdminGlobalBan> _bans = const [];
  bool _loading = false;
  String? _error;
  bool _isNetworkError = false;

  List<AdminGlobalBan> get bans => _bans;
  bool get loading => _loading;
  String? get error => _error;
  bool get isNetworkError => _isNetworkError;

  Future<void> load() async {
    _loading = true;
    _error = null;
    _isNetworkError = false;
    notifyListeners();
    try {
      _bans = await _repository.listGlobalBans();
    } catch (e) {
      _error = _messageFor(e);
      _isNetworkError = e is NetworkException;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> ban(String userId, {String? reason}) async {
    await _repository.globalBan(userId, reason: reason);
    await load();
  }

  Future<void> unban(String userId) async {
    await _repository.globalUnban(userId);
    _bans = _bans.where((b) => b.userId != userId).toList();
    notifyListeners();
  }

  String _messageFor(Object error) {
    if (error is NetworkException) return 'Pas de connexion réseau';
    return 'Impossible de charger les bans';
  }
}
