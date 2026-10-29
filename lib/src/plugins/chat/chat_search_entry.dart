import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_shell_service.dart';

/// The drawer opens the forum's shared search using Chat's current context.
class ChatSearchEntry extends StatelessWidget {
  const ChatSearchEntry({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  Widget build(BuildContext context) {
    final shell = PluginUiScope.require(context, chatShellService);
    return ListenableBuilder(
      listenable: shell,
      builder: (context, _) => shell.searchContextFor(siteUrl) == null
          ? const SizedBox.shrink()
          : DButton(
              key: const ValueKey('chat-search-entry'),
              variant: DButtonVariant.quiet,
              size: DButtonSize.field,
              alignment: AlignmentDirectional.centerStart,
              foregroundColor: DTokens.of(context).mutedForeground,
              icon: const DIcon(DIcons.magnifyingGlass),
              label: Text(context.l10n.searchChat),
              onPressed: () => shell.openGlobalSearch(siteUrl),
            ),
    );
  }
}
