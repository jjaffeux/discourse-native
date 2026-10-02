import 'package:flutter/material.dart';

import '../models/forum_workspace.dart';
import 'composer_presentation.dart';
import 'forum_tabs_bar.dart';
import 'platform.dart';
import 'reader_content_bounds.dart';
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
  const TopicPanelTabs({
    super.key,
    this.panel,
    this.incomingTabId,
    this.trailing,
  });
  final ForumPanel? panel;
  final String? incomingTabId;

  /// An action on the panel itself, after its tabs.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    if (context.isTouch) return const SizedBox.shrink();
    final target = panel ?? ForumTabScope.panelOf(context);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          target != null &&
          shell.currentWorkspace?.tabById(details.data)?.panel != target &&
          shell.currentWorkspace?.tabById(details.data) != null,
      onAcceptWithDetails: (details) =>
          shell.moveTabToPanel(details.data, target!),
      // Keep the mockup's header height even when this panel has no tabs.
      // The tab strip already owns the controls' insets.
      builder: (context, candidates, rejected) => SizedBox(
        height: ForumTabsBar.heightFor(context),
        child: Row(
          children: [
            Expanded(
              child: shell.forumTabsEnabled
                  ? CurrentForumTabsBar(
                      panel: target,
                      incomingTabId: candidates.firstOrNull ?? incomingTabId,
                    )
                  : const SizedBox.shrink(),
            ),
            if (trailing case final action?)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 10),
                child: action,
              ),
          ],
        ),
      ),
    );
  }
}
