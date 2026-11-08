import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_controller.dart';
import 'chat_plugin_data.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';

enum ChatBrowsePage { chats, channels, threads }

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

typedef _ChatInboxNavigationLinks = ({
  bool visible,
  bool channels,
  bool threads,
});

class ChatInboxNavigation extends StatelessWidget {
  const ChatInboxNavigation({super.key, required this.siteUrl});
  final String siteUrl;

  _ChatInboxNavigationLinks _links(ChatShellService shell) {
    if (!shell.isConnected(siteUrl) || !shell.chatAvailable(siteUrl)) {
      return (visible: false, channels: false, threads: false);
    }
    final settings = shell.chat.siteConfigFor(siteUrl).chatSettings;
    return (
      visible: true,
      channels: settings.publicChannelsEnabled,
      threads: settings.threadsEnabled,
    );
  }

  // Availability follows the shell. A refreshed site setting can land without
  // a shell notification, so the links also re-read on chat notifications;
  // those arrive for every message, hence selecting rather than rebuilding.
  @override
  Widget build(
    BuildContext context,
  ) => PluginServiceSelector<ChatShellService, _ChatInboxNavigationLinks>(
    service: chatShellService,
    select: _links,
    builder: (context, _, _) {
      final shell = PluginUiScope.require(context, chatShellService);
      return PluginServiceSelector<ChatController, _ChatInboxNavigationLinks>(
        service: chatControllerService,
        select: (_) => _links(shell),
        builder: (context, links, _) => !links.visible
            ? const SizedBox.shrink()
            : DReferenceTextScale(
                child: Wrap(
                  key: const ValueKey('chat-inbox-navigation'),
                  spacing: DSpacing.sm,
                  runSpacing: DSpacing.sm,
                  children: [
                    if (links.channels)
                      DButton(
                        key: const ValueKey('chat-inbox-channels-card'),
                        variant: DButtonVariant.quiet,
                        size: DControlSize.filter,
                        icon: const DIcon(DIcons.hashtag),
                        label: Text(context.l10n.browseChannels),
                        onPressed: () => shell.openBrowseChannels(),
                      ),
                    if (links.threads)
                      DButton(
                        key: const ValueKey('chat-inbox-threads-card'),
                        variant: DButtonVariant.quiet,
                        size: DControlSize.filter,
                        icon: const DIcon(DIcons.comments),
                        label: Text(context.l10n.threads),
                        onPressed: () => shell.openMyThreads(),
                      ),
                  ],
                ),
              ),
      );
    },
  );
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
  Widget build(BuildContext context) => DReferenceTextScale(
    child: DDropdownMenu(
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
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
