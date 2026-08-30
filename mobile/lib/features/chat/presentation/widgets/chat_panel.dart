import 'package:flutter/material.dart';

import '../providers/chat_controller.dart';
import 'chat_input_bar.dart';
import 'chat_message_bubble.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.controller,
    required this.currentUserId,
  });

  final ChatController controller;
  final String currentUserId;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _scrollController = ScrollController();
  int _previousMessageCount = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onMessagesChanged);
  }

  void _onMessagesChanged() {
    final count = widget.controller.messages.length;
    if (count > _previousMessageCount && _isNearBottom) {
      _previousMessageCount = count;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom();
      });
    }
    _previousMessageCount = count;
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.pixels >= pos.maxScrollExtent - 60;
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onMessagesChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final chat = widget.controller;

    if (chat.error != null && !chat.isConnected) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            chat.error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.error),
          ),
        ),
      );
    }

    return Column(
      children: [
        if (chat.transientError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: colors.errorContainer,
            child: Text(
              chat.transientError!,
              style: TextStyle(color: colors.onErrorContainer, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        Expanded(
          child: chat.messages.isEmpty
              ? Center(
                  child: Text(
                    chat.isConnected
                        ? 'Soyez le premier à écrire !'
                        : 'Connexion…',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: chat.messages.length,
                  itemBuilder: (context, index) {
                    final msg = chat.messages[index];
                    final isOwn = msg.userId == widget.currentUserId;
                    return ChatMessageBubble(
                      message: msg,
                      isOwn: isOwn,
                      isBroadcaster: chat.isBroadcaster,
                      isUserBanned: chat.isUserBanned(msg.userId),
                      onDelete: () => chat.deleteMessage(msg.id),
                      onBan: () => chat.banUser(msg.userId),
                      onUnban: () => chat.unbanUser(msg.userId),
                    );
                  },
                ),
        ),
        ChatInputBar(
          onSend: chat.sendMessage,
          enabled: chat.isConnected,
        ),
      ],
    );
  }
}
