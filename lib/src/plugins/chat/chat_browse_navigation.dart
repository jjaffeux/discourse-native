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
    return DToggleGroup<ChatBrowsePage>(
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
        ChatBrowsePage.chats => shell.openChats(newTab: true),
        ChatBrowsePage.channels => shell.openBrowseChannels(newTab: true),
        ChatBrowsePage.threads => shell.openMyThreads(newTab: true),
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
    this.emphasized = false,
    this.mobileSheetVariant = DSheetVariant.standard,
  });

  final String label;
  final String semanticLabel;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final Widget? icon;
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
