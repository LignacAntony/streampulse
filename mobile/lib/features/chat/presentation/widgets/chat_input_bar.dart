import 'package:flutter/material.dart';

import '../../../../core/widgets/accessible_icon_button.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSend,
    this.enabled = true,
  });

  final ValueChanged<String> onSend;
  final bool enabled;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: widget.enabled,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              maxLength: 500,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: widget.enabled ? 'Écrire un message…' : 'Chat indisponible',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: colors.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                counterText: '',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 6),
          AccessibleIconButton(
            icon: Icons.send,
            label: 'Envoyer le message',
            onPressed: widget.enabled ? _submit : null,
            color: widget.enabled ? colors.primary : colors.outline,
          ),
        ],
      ),
    );
  }
}
