import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/chat/data/datasources/chat_websocket_source.dart';
import 'package:streampulse/features/chat/presentation/providers/chat_controller.dart';

class _FakeChatWebSocketSource implements ChatWebSocketSource {
  StreamController<Map<String, dynamic>>? _controller;
  final List<Map<String, dynamic>> sent = [];
  bool disconnected = false;

  @override
  Stream<Map<String, dynamic>> connect(String streamId) {
    _controller = StreamController<Map<String, dynamic>>.broadcast();
    disconnected = false;
    return _controller!.stream;
  }

  @override
  void send(Map<String, dynamic> message) => sent.add(message);

  @override
  void disconnect() {
    disconnected = true;
    _controller?.close();
    _controller = null;
  }

  void emit(Map<String, dynamic> event) => _controller?.add(event);
}

void main() {
  late _FakeChatWebSocketSource source;
  late ChatController controller;

  setUp(() {
    source = _FakeChatWebSocketSource();
    controller = ChatController(source);
  });

  tearDown(() {
    controller.dispose();
  });

  test('connect sets isConnected after connected event', () async {
    await controller.connect('stream-1', 'user-1');
    expect(controller.isConnected, isFalse);

    source.emit({'type': 'connected', 'is_broadcaster': false});
    await Future<void>.delayed(Duration.zero);
    expect(controller.isConnected, isTrue);
  });

  test('connected event sets isBroadcaster', () async {
    await controller.connect('stream-1', 'user-1');
    source.emit({'type': 'connected', 'is_broadcaster': true});
    await Future<void>.delayed(Duration.zero);

    expect(controller.isBroadcaster, isTrue);
  });

  test('history event populates messages', () async {
    await controller.connect('stream-1', 'user-1');
    source.emit({
      'type': 'history',
      'messages': [
        {
          'id': 'msg-1',
          'user_id': 'u1',
          'username': 'alice',
          'content': 'hello',
          'created_at': '2026-01-01T00:00:00Z',
        },
        {
          'id': 'msg-2',
          'user_id': 'u2',
          'username': 'bob',
          'content': 'hi',
          'created_at': '2026-01-01T00:00:01Z',
        },
      ],
    });
    await Future<void>.delayed(Duration.zero);

    expect(controller.messages.length, 2);
    expect(controller.messages[0].content, 'hello');
    expect(controller.messages[1].content, 'hi');
  });

  test('message event appends to list', () async {
    await controller.connect('stream-1', 'user-1');
    source.emit({
      'type': 'message',
      'id': 'msg-1',
      'user_id': 'u1',
      'username': 'alice',
      'content': 'hello',
      'created_at': '2026-01-01T00:00:00Z',
    });
    await Future<void>.delayed(Duration.zero);

    expect(controller.messages.length, 1);
    expect(controller.messages[0].id, 'msg-1');
  });

  test('delete event marks message as deleted', () async {
    await controller.connect('stream-1', 'user-1');
    source.emit({
      'type': 'message',
      'id': 'msg-1',
      'user_id': 'u1',
      'username': 'alice',
      'content': 'hello',
      'created_at': '2026-01-01T00:00:00Z',
    });
    await Future<void>.delayed(Duration.zero);

    source.emit({'type': 'delete', 'message_id': 'msg-1'});
    await Future<void>.delayed(Duration.zero);

    expect(controller.messages[0].isDeleted, isTrue);
  });

  test('ban event for current user disconnects with error', () async {
    await controller.connect('stream-1', 'user-1');
    source.emit({'type': 'ban', 'user_id': 'user-1'});
    await Future<void>.delayed(Duration.zero);

    expect(controller.isConnected, isFalse);
    expect(controller.error, contains('banni'));
  });

  test('sendMessage sends correct JSON', () async {
    await controller.connect('stream-1', 'user-1');
    source.emit({'type': 'connected', 'is_broadcaster': false});
    await Future<void>.delayed(Duration.zero);

    controller.sendMessage('hello world');

    expect(source.sent.length, 1);
    expect(source.sent[0]['type'], 'message');
    expect(source.sent[0]['content'], 'hello world');
  });

  test('sendMessage trims whitespace', () async {
    await controller.connect('stream-1', 'user-1');
    source.emit({'type': 'connected', 'is_broadcaster': false});
    await Future<void>.delayed(Duration.zero);

    controller.sendMessage('  hello  ');

    expect(source.sent[0]['content'], 'hello');
  });

  test('sendMessage ignores empty content', () async {
    await controller.connect('stream-1', 'user-1');
    source.emit({'type': 'connected', 'is_broadcaster': false});
    await Future<void>.delayed(Duration.zero);

    controller.sendMessage('   ');

    expect(source.sent, isEmpty);
  });

  test('deleteMessage sends correct JSON', () async {
    await controller.connect('stream-1', 'user-1');
    source.emit({'type': 'connected', 'is_broadcaster': true});
    await Future<void>.delayed(Duration.zero);

    controller.deleteMessage('msg-1');

    expect(source.sent.length, 1);
    expect(source.sent[0]['type'], 'delete');
    expect(source.sent[0]['message_id'], 'msg-1');
  });

  test('deleteMessage does nothing if not broadcaster', () async {
    await controller.connect('stream-1', 'user-1');
    controller.deleteMessage('msg-1');

    expect(source.sent, isEmpty);
  });

  test('disconnect clears state', () async {
    await controller.connect('stream-1', 'user-1');
    controller.disconnect();

    expect(controller.isConnected, isFalse);
    expect(controller.isBroadcaster, isFalse);
  });
}
