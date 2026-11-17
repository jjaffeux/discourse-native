import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_shell_service.dart';

enum ChatBrowsePage { chats, threads }

/// Directory pages return to the inbox, which owns their entry cards.
class ChatBrowseBack extends StatelessWidget {
  const ChatBrowseBack({super.key});

  @override
  Widget build(BuildContext context) => DReferenceTextScale(
    child: DButton(
      key: const ValueKey('chat-inbox-back'),
      variant: DButtonVariant.quiet,
      size: DControlSize.filter,
      icon: const DIcon(DIcons.arrowLeft),
      label: Text(context.l10n.chats),
      onPressed: () =>
          PluginUiScope.require(context, chatShellService).openChats(),
    ),
  );
}
