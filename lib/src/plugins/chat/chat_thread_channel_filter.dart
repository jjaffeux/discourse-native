import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_channel.dart';
import 'chat_channel_panel.dart';
import 'chat_thread_directory.dart';

/// The Threads page's channel pill: the dimension until it is narrowed, then
/// the channel it was narrowed to. Pressing it opens the channel panel to
/// pick from.
class ChatThreadChannelFilter extends StatelessWidget {
  const ChatThreadChannelFilter({
    super.key,
    required this.directory,
    required this.onSelected,
  });

  final ChatThreadDirectory directory;
  ChatChannel? get selected => directory.selectedChannel;

  final ValueChanged<ChatChannel?> onSelected;

  Future<void> _pick(BuildContext context) async {
    final choice = await showChatChannelPicker(context, directory: directory);
    if (choice == null || !directory.isCurrent || !context.mounted) return;
    onSelected(choice.channel);
  }

  @override
  Widget build(BuildContext context) {
    final selected = this.selected;
    final label = selected?.title ?? context.l10n.channel;
    return DReferenceTextScale(
      child: DButton(
        key: const ValueKey('chat-threads-channel-filter'),
        size: DButtonSize.filter,
        variant: selected == null
            ? DButtonVariant.quiet
            : DButtonVariant.quietSelected,
        semanticLabel: '${context.l10n.channel}, $label',
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        icon: Text(
          '■',
          style: TextStyle(
            color:
                selected?.categoryColor ?? DTokens.of(context).mutedForeground,
          ),
        ),
        hasPopup: true,
        onPressed: () => _pick(context),
      ),
    );
  }
}
