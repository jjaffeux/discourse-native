import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

import '../models/forum_workspace.dart';
import 'adaptive_shell.dart';
import 'forum_theme_surfaces.dart';
import 'main_content.dart';
import 'resizable_pane.dart';
import 'shell_metrics.dart';
import 'shell_panel.dart';
import 'shell_scope.dart';
import 'topic_presentation.dart';

/// Two document panels whose identities survive swapping their positions.
class DesktopPanels extends StatefulWidget {
  const DesktopPanels({super.key});

  @override
  State<DesktopPanels> createState() => _DesktopPanelsState();
}

class _DesktopPanelsState extends State<DesktopPanels> {
  final _panelKeys = {
    for (final panel in ForumPanel.values) panel: GlobalKey(),
  };
  // Tab-strip and focus changes must not rebuild an unchanged document.
  final _tabContents = <(String, String), MainContent>{};
  final _mainWidth = PanelWidthController(
    initialWidth: 400 + workspacePanelGap,
    minimumWidth: 320 + workspacePanelGap,
  );

  @override
  void dispose() {
    _mainWidth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    _tabContents.removeWhere(
      (owner, _) => shell.workspaceFor(owner.$1)?.tabById(owner.$2) == null,
    );
    final swapped =
        TopicPresentationPreferences.maybeControllerOf(context)?.readerOnLeft ??
        false;
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 640 + workspacePanelGap;
        shell.topicPanelsVisible = horizontal;
        Widget panel(ForumPanel panel) {
          final tab = shell.selectedTabIn(panel);
          return _DesktopPanel(
            key: _panelKeys[panel],
            content: tab == null
                ? null
                : _tabContents.putIfAbsent(
                    (shell.currentInstance!.url, tab.id),
                    () => MainContent(
                      key: GlobalKey(),
                      layout: ShellLayout.expanded,
                    ),
                  ),
            panel: panel,
            tab: tab,
            showHeader: horizontal,
          );
        }

        final main = panel(ForumPanel.main);
        final secondary = panel(ForumPanel.secondary);
        if (!horizontal) {
          final active = shell.activeTab?.panel ?? ForumPanel.main;
          return Column(
            children: [
              for (final target
                  in swapped ? ForumPanel.values.reversed : ForumPanel.values)
                ForumTabScope(
                  tabId: shell.selectedTabIn(target)?.id,
                  panel: target,
                  child: TopicPanelTabs(panel: target),
                ),
              Expanded(
                child: Stack(
                  children: [
                    for (final (target, child) in [
                      (ForumPanel.main, main),
                      (ForumPanel.secondary, secondary),
                    ])
                      Positioned.fill(
                        child: Offstage(
                          offstage: active != target,
                          child: TickerMode(
                            enabled: active == target,
                            child: ExcludeFocus(
                              excluding: active != target,
                              child: child,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            if (swapped) Expanded(child: secondary),
            ResizablePane(
              controller: _mainWidth,
              edge: swapped
                  ? ResizablePaneEdge.leading
                  : ResizablePaneEdge.trailing,
              resizeKey: 'main-panel',
              semanticsLabel: 'Resize main panel',
              maximumWidth: constraints.maxWidth - 320,
              gap: workspacePanelGap,
              handleWidth: workspacePanelGap,
              child: main,
            ),
            if (!swapped) Expanded(child: secondary),
          ],
        );
      },
    );
  }
}

class _DesktopPanel extends StatelessWidget {
  const _DesktopPanel({
    super.key,
    required this.panel,
    required this.tab,
    this.content,
    this.showHeader = true,
  });

  final bool showHeader;
  final MainContent? content;
  final ForumPanel panel;
  final ForumTab? tab;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    void activate() {
      if (tab case final tab? when shell.activeTab?.panel != panel) {
        shell.selectTab(tab.id);
      }
    }

    return ForumTabScope(
      tabId: tab?.id,
      panel: panel,
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) {
          final source = shell.currentWorkspace?.tabById(details.data);
          return source != null && source.panel != panel;
        },
        onAcceptWithDetails: (details) =>
            shell.moveTabToPanel(details.data, panel),
        builder: (context, candidates, rejected) => WorkspacePanel(
          key: ValueKey('desktop-panel-${panel.name}'),
          atRightEdge: true,
          child: Column(
            children: [
              if (showHeader)
                TopicPanelTabs(
                  panel: panel,
                  incomingTabId: candidates.firstOrNull,
                ),
              Expanded(
                child: Focus(
                  canRequestFocus: false,
                  onFocusChange: (focused) {
                    if (focused) activate();
                  },
                  child: Listener(
                    onPointerDown: (_) => activate(),
                    child: tab == null
                        ? DPageSurface(
                            border: false,
                            backgroundColor: ForumWindowBackground.panelColor(
                              context,
                            ),
                            child: Center(
                              child: DEmpty(
                                children: [
                                  DEmptyHeader(
                                    children: [
                                      DEmptyTitle(
                                        panel == ForumPanel.main
                                            ? 'Main panel'
                                            : 'Secondary panel',
                                      ),
                                      DEmptyDescription(
                                        candidates.isNotEmpty
                                            ? 'Drop this tab here'
                                            : 'Drag a tab here or open a new tab.',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          )
                        : content!,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
