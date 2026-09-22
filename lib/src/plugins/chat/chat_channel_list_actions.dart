import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

import 'chat_channel_list_controller.dart';
import 'chat_channel_list_preferences.dart';

class ChatChannelListActions extends StatelessWidget {
  const ChatChannelListActions({
    super.key,
    required this.controller,
    required this.siteUrl,
    required this.section,
    this.showFilterToggle = true,
  });

  final ChatChannelListController controller;
  final String siteUrl;
  final ChatChannelListSection section;
  final bool showFilterToggle;

  String get _label => switch (section) {
    ChatChannelListSection.channels => 'Channels',
    ChatChannelListSection.starred => 'Starred channels',
    ChatChannelListSection.directMessages => 'Direct messages',
  };

  Future<void> _save(BuildContext context, Future<bool> save) async {
    if (!await save && context.mounted) {
      final error = controller.errorFor(siteUrl, section);
      if (error != null) DToast.show(context, error, type: DToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final preferences = controller.preferencesFor(siteUrl);
      if (!preferences.supportsSection(section)) return const SizedBox.shrink();
      final filter = preferences.filterFor(section);
      final sort = preferences.sortFor(section);
      final bypassed = controller.bypassed(siteUrl, section);
      final savingFilter = controller.saving(siteUrl, section.filterField);
      final savingSort = controller.saving(siteUrl, section.sortField);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (filter != ChatChannelListFilter.all &&
              (showFilterToggle || bypassed))
            DButton.iconOnly(
              key: ValueKey('chat-filter-toggle-${section.name}'),
              icon: DIcon(bypassed ? DIcons.filter : DIcons.farEye),
              tooltip: bypassed
                  ? 'Reapply filter: $_label'
                  : 'Show all: $_label',
              semanticLabel: bypassed
                  ? 'Reapply filter: $_label'
                  : 'Show all: $_label',
              variant: DButtonVariant.ghost,
              size: DButtonSize.small,
              onPressed: savingFilter
                  ? null
                  : () => controller.toggleFilter(siteUrl, section),
            ),
          DDropdownMenu(
            content: DDropdownMenuContent(
              semanticLabel: '$_label options',
              children: [
                if (controller.errorFor(siteUrl, section) case final error?)
                  DDropdownMenuLabel(child: Text(error)),
                if (preferences.supports(section.filterField)) ...[
                  const DDropdownMenuLabel(child: Text('Filter')),
                  DDropdownMenuRadioGroup<ChatChannelListFilter>(
                    value: filter,
                    onChanged: savingFilter
                        ? null
                        : (value) => unawaited(
                            _save(
                              context,
                              controller.setFilter(siteUrl, section, value),
                            ),
                          ),
                    children: [
                      for (final value in ChatChannelListFilter.values)
                        DDropdownMenuRadioItem(
                          value: value,
                          child: Text(value.label),
                        ),
                    ],
                  ),
                ],
                if (preferences.supports(section.sortField)) ...[
                  if (preferences.supports(section.filterField))
                    const DDropdownMenuSeparator(),
                  const DDropdownMenuLabel(child: Text('Sort')),
                  DDropdownMenuRadioGroup<ChatChannelListSort>(
                    value: sort,
                    onChanged: savingSort
                        ? null
                        : (value) => unawaited(
                            _save(
                              context,
                              controller.setSort(siteUrl, section, value),
                            ),
                          ),
                    children: [
                      for (final value in ChatChannelListSort.values)
                        DDropdownMenuRadioItem(
                          value: value,
                          child: Text(value.label),
                        ),
                    ],
                  ),
                ],
              ],
            ),
            child: DDropdownMenuTrigger(
              builder: (context, state) => DButton.iconOnly(
                key: ValueKey('chat-list-options-${section.name}'),
                tooltip: '$_label options',
                semanticLabel: '$_label options',
                icon: const DIcon(DIcons.ellipsis),
                variant: DButtonVariant.ghost,
                size: DButtonSize.small,
                focusNode: state.focusNode,
                hasPopup: true,
                expanded: state.open,
                onPressed: state.toggle,
              ),
            ),
          ),
        ],
      );
    },
  );
}
