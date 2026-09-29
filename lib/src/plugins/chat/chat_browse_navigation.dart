import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_plugin_data.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';

enum ChatBrowsePage { chats, channels, threads }

/// The three chat directories are peers, with the same navigation on each.
class ChatBrowseNavigation extends StatelessWidget {
  const ChatBrowseNavigation({
    super.key,
    required this.siteUrl,
    required this.page,
  });

  final String siteUrl;
  final ChatBrowsePage page;

  @override
  Widget build(BuildContext context) {
    final shell = PluginUiScope.require(context, chatShellService);
    final settings = PluginUiScope.require(
      context,
      chatControllerService,
    ).siteConfigFor(siteUrl).chatSettings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DSpacing.md,
      children: [
        Text(
          switch (page) {
            ChatBrowsePage.chats => context.l10n.browseChats,
            ChatBrowsePage.channels => context.l10n.browseChannels,
            ChatBrowsePage.threads => context.l10n.browseThreads,
          },
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontSize: DiscourseTypography.xxl,
            fontWeight: FontWeight.w700,
          ),
        ),
        DToggleGroup<ChatBrowsePage>(
          key: const ValueKey('chat-browse-navigation'),
          inset: true,
          size: DControlSize.segment,
          scrollable: true,
          allowEmptySelection: false,
          values: [page],
          semanticLabel: context.l10n.browseChat,
          items: [
            DToggleGroupItem(
              value: ChatBrowsePage.chats,
              icon: const DIcon(DIcons.comment),
              child: Text(context.l10n.chats),
            ),
            if (settings.publicChannelsEnabled)
              DToggleGroupItem(
                value: ChatBrowsePage.channels,
                icon: const Text('#'),
                child: Text(context.l10n.channels),
              ),
            if (settings.threadsEnabled)
              DToggleGroupItem(
                value: ChatBrowsePage.threads,
                icon: const DIcon(DIcons.comments),
                child: Text(context.l10n.threads),
              ),
          ],
          onChanged: (values) => switch (values.single) {
            ChatBrowsePage.chats => shell.openChats(),
            ChatBrowsePage.channels => shell.openBrowseChannels(),
            ChatBrowsePage.threads => shell.openMyThreads(),
          },
        ),
      ],
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
    required this.entries,
    required this.onChanged,
    this.icon,
    this.emphasized = false,
  });

  final String label;
  final String semanticLabel;
  final T value;
  final List<DSelectEntry<T>> entries;
  final ValueChanged<T> onChanged;
  final Widget? icon;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => DSelect<T>.controlled(
    size: DControlSize.filter,
    value: value,
    semanticLabel: semanticLabel,
    entries: entries,
    width: 220,
    align: DPopoverAlign.start,
    alignItemWithTrigger: false,
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
    triggerBuilder: (context, state, _) => DButton(
      size: DControlSize.filter,
      variant: DButtonVariant.outline,
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
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          const DIcon(DNativeIcons.filterChevron, size: 10),
        ],
      ),
    ),
  );
}
