import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'chat_drawer.dart';

/// Uses the same channel queries, unread state and row actions as desktop Chat.
class ChatMobileSidebar extends StatefulWidget {
  const ChatMobileSidebar({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<ChatMobileSidebar> createState() => _ChatMobileSidebarState();
}

class _ChatMobileSidebarState extends State<ChatMobileSidebar> {
  ChatDrawerChannelListKind _kind = ChatDrawerChannelListKind.channels;

  @override
  Widget build(BuildContext context) => ChatDrawerChannelsView(
    siteUrl: widget.siteUrl,
    kind: _kind,
    header: DTabs<ChatDrawerChannelListKind>.controlled(
      value: _kind,
      onChanged: (value) {
        if (value != null) setState(() => _kind = value);
      },
      children: const [
        DTabList<ChatDrawerChannelListKind>(
          variant: DTabListVariant.line,
          children: [
            DTabTrigger(
              value: ChatDrawerChannelListKind.channels,
              child: Text('Channels'),
            ),
            DTabTrigger(
              value: ChatDrawerChannelListKind.directMessages,
              child: Text('DMs'),
            ),
          ],
        ),
      ],
    ),
  );
}
