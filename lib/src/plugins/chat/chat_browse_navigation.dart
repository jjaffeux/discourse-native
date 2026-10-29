import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'chat_controller.dart';
import 'chat_plugin_data.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';
import 'chat_thread_directory.dart';

enum ChatBrowsePage { chats, channels, threads }

/// Directory pages return to the inbox, which owns their entry cards.
class ChatBrowseBack extends StatelessWidget {
  const ChatBrowseBack({super.key});

  @override
  Widget build(BuildContext context) => DButton(
    key: const ValueKey('chat-inbox-back'),
    variant: DButtonVariant.quiet,
    size: DControlSize.filter,
    icon: const DIcon(DIcons.arrowLeft),
    label: Text(context.l10n.chats),
    onPressed: () =>
        PluginUiScope.require(context, chatShellService).openChats(),
  );
}

class ChatInboxNavigation extends StatefulWidget {
  const ChatInboxNavigation({super.key, required this.siteUrl});
  final String siteUrl;

  @override
  State<ChatInboxNavigation> createState() => _ChatInboxNavigationState();
}

class _ChatInboxNavigationState extends State<ChatInboxNavigation> {
  ChatController? _chat;
  ChatThreadDirectory? _directory;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(ChatInboxNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind();
  }

  void _bind() {
    final chat = PluginUiScope.require(context, chatControllerService);
    if (identical(chat, _chat) &&
        _directory?.siteUrl == widget.siteUrl &&
        _directory?.isCurrent == true) {
      return;
    }
    _directory?.dispose();
    _chat = chat;
    _directory = ChatThreadDirectory(chat, widget.siteUrl);
    if (chat.siteConfigFor(widget.siteUrl).chatSettings.threadsEnabled) {
      unawaited(_directory!.load());
    }
  }

  @override
  void dispose() {
    _directory?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat!;
    final directory = _directory!;
    final shell = PluginUiScope.require(context, chatShellService);
    return ListenableBuilder(
      listenable: Listenable.merge([chat, directory]),
      builder: (context, _) {
        final settings = chat.siteConfigFor(widget.siteUrl).chatSettings;
        final joined = chat
            .publicChannels(widget.siteUrl)
            .where((c) => c.membership.following)
            .length;
        final numbers = NumberFormat('0', context.l10n.localeName);
        final joinedNote = chat.channelsLoaded(widget.siteUrl)
            ? context.l10n.chatJoinedChannelCount(numbers.format(joined))
            : chat.channelsError(widget.siteUrl) != null
            ? context.l10n.couldNotLoadConversations
            : context.l10n.loading;
        final count = directory.threads.length;
        final moreThreads = directory.hasMore(null);
        // The API supplies pages without a total. A plus names the lower bound
        // rather than presenting the first page as the forum's complete count.
        final threadNote = !directory.loaded && directory.loading
            ? context.l10n.loading
            : directory.error(null) != null
            ? context.l10n.couldNotLoadConversations
            : moreThreads
            ? context.l10n.chatThreadCountLowerBound(numbers.format(count))
            : countLabel(count, CountNoun.thread);
        return Padding(
          key: const ValueKey('chat-inbox-navigation'),
          padding: const EdgeInsets.only(top: DSpacing.xs, bottom: DSpacing.xs),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cards = <Widget>[
                if (settings.publicChannelsEnabled)
                  DPlaceCard(
                    key: const ValueKey('chat-inbox-channels-card'),
                    leading: const DIcon(DIcons.hashtag),
                    title: Text(context.l10n.channels),
                    footer: Text(joinedNote),
                    onPressed: () => shell.openBrowseChannels(),
                  ),
                if (settings.threadsEnabled)
                  DPlaceCard(
                    key: const ValueKey('chat-inbox-threads-card'),
                    leading: const DIcon(DIcons.comments),
                    title: Text(context.l10n.threads),
                    footer: Text(threadNote),
                    onPressed: () => shell.openMyThreads(),
                  ),
              ];
              if (constraints.maxWidth <
                  MediaQuery.textScalerOf(context).scale(300)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: DSpacing.sm,
                  children: cards,
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: DSpacing.sm,
                children: [for (final card in cards) Expanded(child: card)],
              );
            },
          ),
        );
      },
    );
  }
}

/// A directory filter names its dimension until the reader narrows it.
class ChatBrowseFilter<T> extends StatelessWidget {
  const ChatBrowseFilter({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
    this.optionIcons = const {},
    this.emphasized = false,
    this.mobileSheetVariant = DSheetVariant.adaptiveMenu,
  });

  final String label;
  final String semanticLabel;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final Widget? icon;
  final Map<T, Widget> optionIcons;
  final bool emphasized;
  final DSheetVariant mobileSheetVariant;

  @override
  Widget build(BuildContext context) => DDropdownMenu(
    sheetOnMobile: true,
    mobileSheetVariant: mobileSheetVariant,
    content: DDropdownMenuContent(
      width: 220,
      align: DPopoverAlign.start,
      semanticLabel: semanticLabel,
      children: [
        DDropdownMenuRadioGroup<T>(
          value: value,
          onChanged: onChanged,
          children: [
            for (final option in options.entries)
              DDropdownMenuRadioItem<T>(
                value: option.key,
                closeOnSelect: true,
                leading: optionIcons[option.key],
                child: Text(option.value),
              ),
          ],
        ),
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, state) => DButton(
        size: DControlSize.filter,
        variant: emphasized
            ? DButtonVariant.quietSelected
            : DButtonVariant.quiet,
        semanticLabel: '$semanticLabel, $label',
        focusNode: state.focusNode,
        hasPopup: true,
        expanded: state.open,
        onPressed: state.toggle,
        icon: icon,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DSpacing.controlGap,
          children: [
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    ),
  );
}
