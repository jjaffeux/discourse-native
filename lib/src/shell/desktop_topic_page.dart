import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../theme/d_icons.dart';
import 'forum_search.dart';
import 'platform.dart';
import 'shell_scope.dart';
import 'title_bar.dart';
import 'topic_list_bottom_bar.dart';

/// A conversation page with navigation back to its source list.
class DesktopTopicPage extends StatelessWidget {
  const DesktopTopicPage({
    super.key,
    required this.child,
    this.sourceListVisible = false,
  });

  final Widget child;
  final bool sourceListVisible;

  @override
  Widget build(BuildContext context) {
    if (context.isTouch) return child;
    return Column(
      children: [
        if (!sourceListVisible && !ShellTitleBar.isSupported)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: ForumSearch(dense: true),
          ),
        _TopicPageNavigation(sourceListVisible: sourceListVisible),
        Expanded(child: child),
      ],
    );
  }
}

class _TopicPageNavigation extends StatefulWidget {
  const _TopicPageNavigation({required this.sourceListVisible});

  final bool sourceListVisible;

  @override
  State<_TopicPageNavigation> createState() => _TopicPageNavigationState();
}

class _TopicPageNavigationState extends State<_TopicPageNavigation> {
  final _switcher = DComboboxController<int>();

  @override
  void dispose() {
    _switcher.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    return ListenableBuilder(
      listenable: Listenable.merge([shell, shell.topicFeeds]),
      builder: (context, _) {
        final source = shell.topicListContent;
        final siteUrl = shell.currentInstance?.url;
        final tabId = shell.activeTabId;
        final feedId = shell.currentFeedId;
        final route = shell.currentContent;
        final ids = shell.currentFeed?.topicIds ?? const <int>[];
        final topics = [
          if (siteUrl != null)
            for (final id in ids) ?shell.store.read<Topic>(siteUrl, id),
        ];
        final index = ids.indexOf(route?.topicId ?? -1);
        return Padding(
          key: const ValueKey('topic-page-navigation'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth /
                      MediaQuery.textScalerOf(context).scale(1) <
                  440;
              final label = source?.isMessages == true ? 'Messages' : 'Topics';
              void back() => shell.closeTopic();
              return Row(
                children: [
                  if (compact)
                    DButton.iconOnly(
                      key: const ValueKey('topic-page-back'),
                      icon: const DIcon(DIcons.arrowLeft),
                      tooltip: 'Back to $label',
                      variant: DButtonVariant.ghost,
                      onPressed: back,
                    )
                  else
                    DButton(
                      key: const ValueKey('topic-page-back'),
                      icon: const DIcon(DIcons.arrowLeft),
                      label: Text(source == null ? 'Back' : label),
                      tooltip: source == null ? 'Back' : 'Back to $label',
                      variant: DButtonVariant.ghost,
                      onPressed: back,
                    ),
                  if (source != null) ...[
                    const SizedBox(width: DSpacing.xs),
                    DCombobox<int>.controlled(
                      // Navigation to another feed or account dismisses its popup.
                      key: ValueKey(('topic-switcher', siteUrl, tabId, feedId)),
                      value: route?.topicId,
                      controller: _switcher,
                      onOpenChanged: (open, _) {
                        if (open) _switcher.setQuery('');
                      },
                      options: [
                        for (final topic in topics)
                          DComboboxOption(
                            value: topic.id,
                            label: topic.title,
                            itemKey: ValueKey(('switch-topic', topic.id)),
                          ),
                      ],
                      onChanged: (id, _) {
                        if (id == null ||
                            shell.currentInstance?.url != siteUrl ||
                            shell.activeTabId != tabId ||
                            shell.currentFeedId != feedId ||
                            shell.currentContent != route) {
                          return;
                        }
                        final topic = topics
                            .where((t) => t.id == id)
                            .firstOrNull;
                        if (topic != null) shell.openTopicFromList(topic);
                      },
                      anchor: DComboboxTrigger<int>(
                        builder: (context, trigger) => compact
                            ? DButton.iconOnly(
                                key: const ValueKey('topic-switcher-trigger'),
                                icon: const DIcon(DIcons.list),
                                tooltip: 'Switch topic',
                                variant: DButtonVariant.outline,
                                focusNode: trigger.focusNode,
                                expanded: trigger.open,
                                hasPopup: true,
                                onPressed: trigger.toggle,
                              )
                            : DButton(
                                key: const ValueKey('topic-switcher-trigger'),
                                label: const Text('Switch topic'),
                                icon: const DIcon(DIcons.chevronDown),
                                iconPosition: DButtonIconPosition.end,
                                variant: DButtonVariant.outline,
                                focusNode: trigger.focusNode,
                                expanded: trigger.open,
                                hasPopup: true,
                                onPressed: trigger.toggle,
                              ),
                      ),
                      content: DComboboxContent(
                        width: 380,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(DSpacing.xs),
                            child: DComboboxInput<int>(
                              placeholder: 'Find in this list…',
                              semanticLabel: 'Find a topic in this list',
                              registerAsAnchor: false,
                              showTrigger: false,
                            ),
                          ),
                          const DComboboxEmpty<int>(
                            child: Text('No matching topics'),
                          ),
                          const DComboboxList<int>(),
                          if (shell.currentFeed?.hasMore == true)
                            DButton(
                              label: const Text('Load more topics'),
                              variant: DButtonVariant.ghost,
                              loading: shell.currentFeed?.loadingMore == true,
                              onPressed: feedId == null
                                  ? null
                                  : () => unawaited(shell.loadMoreFeed(feedId)),
                            ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (!compact && index >= 0)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: Text(
                          '${index + 1} / ${ids.length}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (!widget.sourceListVisible)
                      const TopicNavigationButtons(),
                  ] else
                    const Spacer(),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
