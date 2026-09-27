import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'chat_channel.dart';
import 'chat_chrome_scroll_view.dart';
import 'chat_inbox.dart';
import 'chat_plugin_data.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';

/// Mobile's combined inbox keeps its filters while visiting a conversation.
class ChatMobileSidebar extends StatelessWidget {
  const ChatMobileSidebar({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    final shell = PluginUiScope.require(context, chatShellService);
    final filters = chat.inboxFilters;
    return ListenableBuilder(
      listenable: Listenable.merge([chat, filters]),
      builder: (context, _) {
        final settings = chat.siteConfigFor(siteUrl).chatSettings;
        final filter = filters.filterFor(siteUrl);
        final channels = chatInboxConversations(chat, siteUrl, filter);
        final error = chat.channelsError(siteUrl);
        final loading = !chat.channelsLoaded(siteUrl) && error == null;
        final colors = DTokens.of(context);
        Widget row(ChatChannel channel) => ValueListenableBuilder<ChatChannel?>(
          key: ValueKey(channel.id),
          valueListenable: chat.channelRef(siteUrl, channel.id),
          builder: (context, current, _) => ChatInboxRow(
            siteUrl: siteUrl,
            channel: current ?? channel,
            onPressed: () => shell.openChannel(channel.id),
          ),
        );
        final shortcuts =
            settings.publicChannelsEnabled ||
            (settings.threadsEnabled && chat.hasThreads(siteUrl));
        return ChatChromeScrollView(
          header: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Chat', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: DSpacing.md),
                ChatInboxFilterBar(siteUrl: siteUrl, filters: filters),
                const SizedBox(height: DSpacing.sm),
                DSeparator(color: colors.border),
              ],
            ),
          ),
          list: (context, lazy) => loading
              ? const Center(
                  child: DSpinner(semanticLabel: 'Loading conversations'),
                )
              : error != null && channels.isEmpty
              ? ChatInboxError(
                  onRetry: () =>
                      unawaited(chat.loadChannels(siteUrl, force: true)),
                )
              : channels.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(DSpacing.lg),
                    child: Text(
                      chatInboxEmptyMessage(filter),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : lazy
              ? ListView.separated(
                  key: PageStorageKey(('mobile-chat-list', siteUrl, filter)),
                  padding: EdgeInsets.zero,
                  itemCount: channels.length,
                  separatorBuilder: (context, _) =>
                      DSeparator(color: colors.border),
                  itemBuilder: (context, index) => row(channels[index]),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, channel) in channels.indexed) ...[
                      if (index > 0) DSeparator(color: colors.border),
                      row(channel),
                    ],
                  ],
                ),
          footer: shortcuts
              ? DCardFooter(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ChatInboxShortcuts(
                    browse: settings.publicChannelsEnabled,
                    myThreads:
                        settings.threadsEnabled && chat.hasThreads(siteUrl),
                  ),
                )
              : null,
        );
      },
    );
  }
}
