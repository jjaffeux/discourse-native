import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/topic_presentation.dart';
import 'composer_presentation.dart';
import 'forum_tabs_bar.dart';
import 'platform.dart';
import 'reader_content_bounds.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'topic_presentation_controller.dart';

/// Owns the desktop preference across forums, tabs and workspace changes.
class TopicPresentationPreferences extends StatefulWidget {
  const TopicPresentationPreferences({super.key, required this.child});
  final Widget child;

  static TopicPresentationController? maybeControllerOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PreferenceScope>()?.notifier;

  @override
  State<TopicPresentationPreferences> createState() =>
      _TopicPresentationPreferencesState();
}

class _TopicPresentationPreferencesState
    extends State<TopicPresentationPreferences> {
  final _controller = TopicPresentationController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncNavigation);
    unawaited(_controller.load());
  }

  void _syncNavigation() {
    if (!mounted) return;
    ShellScope.read(context).splitTopicPanels =
        _controller.preference == TopicPresentation.split;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ShellScope.read(context).desktopTopicTabs = !context.isTouch;
  }

  @override
  Widget build(BuildContext context) =>
      _PreferenceScope(notifier: _controller, child: widget.child);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _PreferenceScope extends InheritedNotifier<TopicPresentationController> {
  const _PreferenceScope({required super.notifier, required super.child});
}

/// Composer docking surrounds both independently tabbed reading panels.
class TopicWorkspace extends StatelessWidget {
  const TopicWorkspace({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ComposerDock(
    key: ComposerPresentationHost.dockKeyOf(context),
    appWorkspace: true,
    child: ReaderContentBounds(child: child),
  );
}

/// The panel header scopes tab actions to the tabs actually shown in it.
class TopicPanelTabs extends StatelessWidget {
  const TopicPanelTabs({super.key, this.reading, this.split = false});
  final bool? reading;
  final bool split;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    if (context.isTouch) return const SizedBox.shrink();
    final preferences = TopicPresentationPreferences.maybeControllerOf(context);
    return Padding(
      padding: workspaceTabsPadding,
      child: Row(
        children: [
          Expanded(
            child: shell.forumTabsEnabled
                ? CurrentForumTabsBar(reading: reading)
                : const SizedBox.shrink(),
          ),
          if (reading != true && preferences != null && !context.isTouch)
            const TopicPresentationButton(),
          if (split && preferences != null) ...[
            if (reading != true) const SizedBox(width: DSpacing.sm),
            DButton.iconOnly(
              key: ValueKey(
                reading == true
                    ? 'swap-topic-panels-reader'
                    : 'swap-topic-panels-list',
              ),
              icon: const Icon(Icons.swap_horiz),
              tooltip: preferences.readerOnLeft
                  ? 'Move the reading panel right'
                  : 'Move the reading panel left',
              variant: DButtonVariant.transparentBackground,
              onPressed: preferences.swapPanels,
            ),
          ],
        ],
      ),
    );
  }
}

class TopicPresentationButton extends StatelessWidget {
  const TopicPresentationButton({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = TopicPresentationPreferences.maybeControllerOf(context);
    if (context.isTouch || controller == null) return const SizedBox.shrink();
    return DToggleGroup<TopicPresentation>(
      key: const ValueKey('topic-view-options'),
      semanticLabel: 'Topic view',
      inset: true,
      values: [controller.preference],
      allowEmptySelection: false,
      onChanged: (values) {
        controller.select(values.single);
        ShellScope.read(context).splitTopicPanels =
            values.single == TopicPresentation.split;
      },
      items: [
        for (final mode in TopicPresentation.values)
          DToggleGroupItem.iconOnly(
            value: mode,
            semanticLabel: mode.label,
            tooltip: mode.label,
            icon: Icon(
              mode == TopicPresentation.merged
                  ? Icons.copy_outlined
                  : Icons.view_column_outlined,
            ),
          ),
      ],
    );
  }
}
