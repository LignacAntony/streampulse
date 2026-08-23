import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/datasources/chat_websocket_source.dart';
import '../../data/repositories/chat_ban_repository.dart';
import '../../domain/entities/chat_message.dart';

class ChatController extends ChangeNotifier {
  ChatController(this._source, {this.banRepository});

  final ChatWebSocketSource _source;
  final ChatBanRepository? banRepository;

  List<ChatMessage> _messages = [];
  bool _isConnected = false;
  bool _isBroadcaster = false;
  String? _error;
  String? _currentUserId;
  String? _streamId;
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _disposed = false;
  final Set<String> _bannedUserIds = {};

  static const _maxRetries = 3;
  static const _backoffBase = Duration(seconds: 1);
  int _retryCount = 0;
  Timer? _retryTimer;
  bool _explicitDisconnect = false;

  List<ChatMessage> get messages => _messages;
  bool get isConnected => _isConnected;
  bool get isBroadcaster => _isBroadcaster;
  String? get error => _error;

  bool isUserBanned(String userId) => _bannedUserIds.contains(userId);

  Future<void> connect(String streamId, String currentUserId) async {
    if (_isConnected && _streamId == streamId) return;
    disconnect();

    _explicitDisconnect = false;
    _streamId = streamId;
    _currentUserId = currentUserId;
    _error = null;
    _messages = [];
    _retryCount = 0;

    await _doConnect();
  }

  Future<void> _doConnect() async {
    if (_disposed || _explicitDisconnect) return;
    final streamId = _streamId;
    if (streamId == null) return;

    try {
      final stream = _source.connect(streamId);
      _isConnected = true;
      _error = null;
      _notify();

      _sub = stream.listen(
        _onEvent,
        onError: _onStreamError,
        onDone: _onDone,
      );
    } on Object catch (e) {
      _error = 'Impossible de se connecter au chat';
      if (kDebugMode) print('ChatController connect error: $e');
      _notify();
    }
  }

  void sendMessage(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty || !_isConnected) return;
    _source.send({'type': 'message', 'content': trimmed});
  }

  void deleteMessage(String messageId) {
    if (!_isBroadcaster || !_isConnected) return;
    _source.send({'type': 'delete', 'message_id': messageId});
  }

  void banUser(String userId) {
    if (!_isBroadcaster || !_isConnected) return;
    _source.send({'type': 'ban', 'user_id': userId});
  }

  Future<void> unbanUser(String userId) async {
    if (!_isBroadcaster || banRepository == null) return;
    await banRepository!.unban(userId);
    _bannedUserIds.remove(userId);
    _notify();
  }

  void disconnect() {
    _explicitDisconnect = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _sub?.cancel();
    _sub = null;
    _source.disconnect();
    _isConnected = false;
    _isBroadcaster = false;
    _streamId = null;
    _bannedUserIds.clear();
    _notify();
  }

  void _onEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'connected':
        _isBroadcaster = event['is_broadcaster'] == true;
        _retryCount = 0;
        _notify();

      case 'history':
        final list = event['messages'] as List<dynamic>? ?? [];
        _messages = list.map(_parseMessage).toList();
        _notify();

      case 'message':
        _messages = [..._messages, _parseMessage(event)];
        _notify();

      case 'delete':
        final msgId = event['message_id'] as String?;
        if (msgId != null) {
          _messages = _messages.map((m) {
            if (m.id == msgId) return m.copyWith(isDeleted: true);
            return m;
          }).toList();
          _notify();
        }

      case 'ban':
        final bannedId = event['user_id'] as String?;
        if (bannedId == _currentUserId) {
          _error = 'Vous avez été banni de ce chat';
          _explicitDisconnect = true;
          _sub?.cancel();
          _sub = null;
          _source.disconnect();
          _isConnected = false;
          _isBroadcaster = false;
          _bannedUserIds.clear();
          _notify();
        } else if (bannedId != null) {
          _bannedUserIds.add(bannedId);
          _messages = _messages.map((m) {
            if (m.userId == bannedId) return m.copyWith(isDeleted: true);
            return m;
          }).toList();
          _notify();
        }

      case 'error':
        final msg = event['message'] as String? ?? 'Erreur';
        if (msg.contains('banni')) {
          _error = msg;
          _explicitDisconnect = true;
          _isConnected = false;
          _notify();
        } else {
          _error = msg;
          _isConnected = false;
          _notify();
        }
    }
  }

  void _onStreamError(Object error) {
    _isConnected = false;
    _source.disconnect();
    _sub?.cancel();
    _sub = null;
    _scheduleReconnect();
  }

  void _onDone() {
    _isConnected = false;
    _source.disconnect();
    _sub = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _explicitDisconnect) {
      _notify();
      return;
    }
    if (_retryCount >= _maxRetries) {
      _error = 'Connexion au chat perdue';
      _notify();
      return;
    }
    final delay = _backoffBase * (1 << _retryCount);
    _retryCount++;
    _error = null;
    _notify();
    _retryTimer = Timer(delay, _doConnect);
  }

  ChatMessage _parseMessage(dynamic data) {
    final map = data as Map<String, dynamic>;
    return ChatMessage(
      id: map['id'] as String? ?? '',
      userId: map['user_id'] as String? ?? '',
      username: map['username'] as String? ?? '',
      content: map['content'] as String? ?? '',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    disconnect();
    super.dispose();
  }
}
