import 'package:flutter/material.dart';

import '../../domain/entities/chat_message.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isOwn,
    required this.isBroadcaster,
    this.isUserBanned = false,
    this.onDelete,
    this.onBan,
    this.onUnban,
  });

  final ChatMessage message;
  final bool isOwn;
  final bool isBroadcaster;
  final bool isUserBanned;
  final VoidCallback? onDelete;
  final VoidCallback? onBan;
  final VoidCallback? onUnban;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: isBroadcaster && !isOwn ? () => _showActions(context) : null,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isOwn
                ? colors.primaryContainer
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment:
                isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isOwn)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    message.username,
                    style: text.labelSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Text(
                message.isDeleted
                    ? 'Message supprimé'
                    : message.content,
                style: text.bodyMedium?.copyWith(
                  color: isOwn
                      ? colors.onPrimaryContainer
                      : colors.onSurface,
                  fontStyle: message.isDeleted
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Supprimer le message'),
              onTap: () {
                Navigator.of(ctx).pop();
                onDelete?.call();
              },
            ),
            if (isUserBanned)
              ListTile(
                leading: const Icon(Icons.lock_open),
                title: const Text('Débannir cet utilisateur'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onUnban?.call();
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('Bannir cet utilisateur'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onBan?.call();
                },
              ),
          ],
        ),
      ),
    );
  }
}
