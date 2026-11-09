import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_find_field.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';

/// Narrows this forum's sidebar without navigating away from it.
class ChatSearchEntry extends StatefulWidget {
  const ChatSearchEntry({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<ChatSearchEntry> createState() => _ChatSearchEntryState();
}

class _ChatSearchEntryState extends State<ChatSearchEntry> {
  final _focus = FocusNode();
  final _text = TextEditingController();

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = PluginUiScope.require(context, chatShellService);
    final filters = PluginUiScope.require(
      context,
      chatControllerService,
    ).inboxFilters;
    return ListenableBuilder(
      listenable: Listenable.merge([shell, filters]),
      builder: (context, _) {
        if (!shell.isConnected(widget.siteUrl) ||
            !shell.chatAvailable(widget.siteUrl)) {
          return const SizedBox.shrink();
        }
        final query = filters.sidebarQueryFor(widget.siteUrl);
        if (_text.text != query) {
          _text.value = TextEditingValue(
            text: query,
            selection: TextSelection.collapsed(offset: query.length),
          );
        }
        final touch = DControlStyle.isTouch(context);
        return Padding(
          padding: touch
              ? const EdgeInsets.fromLTRB(10, 10, 10, 0)
              : const EdgeInsets.fromLTRB(4, 4, 4, 6),
          child: ChatFindField(
            key: const ValueKey('chat-search-entry'),
            controller: _text,
            focusNode: _focus,
            placeholder: context.l10n.searchChat,
            onChanged: (value) =>
                filters.setSidebarQuery(widget.siteUrl, value),
          ),
        );
      },
    );
  }
}
