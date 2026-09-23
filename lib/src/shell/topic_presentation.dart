import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/forum_workspace.dart';
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
  const TopicPanelTabs({super.key, this.panel});
  final ForumPanel? panel;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    if (context.isTouch) return const SizedBox.shrink();
    final preferences = TopicPresentationPreferences.maybeControllerOf(context);
    final target = panel ?? ForumTabScope.panelOf(context);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          target != null &&
          shell.currentWorkspace?.tabById(details.data)?.panel != target &&
          shell.currentWorkspace?.tabById(details.data) != null,
      onAcceptWithDetails: (details) =>
          shell.moveTabToPanel(details.data, target!),
      builder: (context, candidates, rejected) => Padding(
        padding: workspaceTabsPadding,
        child: Row(
          children: [
            Expanded(
              child: shell.forumTabsEnabled
                  ? CurrentForumTabsBar(panel: target)
                  : const SizedBox.shrink(),
            ),
            if (preferences != null && target != null)
              DButton.iconOnly(
                key: ValueKey('swap-panels-${target.name}'),
                icon: const Icon(Icons.swap_horiz),
                tooltip: 'Switch panel positions',
                variant: DButtonVariant.transparentBackground,
                onPressed: preferences.swapPanels,
              ),
          ],
        ),
      ),
    );
  }
}
