import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

import '../models/forum_workspace.dart';
import '../theme/d_icons.dart';
import 'adaptive_shell.dart';
import 'forum_tabs_bar.dart';
import 'forum_theme_surfaces.dart';
import 'main_content.dart';
import 'panel_rail.dart';
import 'resizable_pane.dart';
import 'shell_metrics.dart';
import 'shell_panel.dart';
import 'shell_scope.dart';
import 'topic_presentation.dart';

/// Two document panels whose identities survive either one being minimized.
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

  // Only one panel stands down at a time, or there would be nothing left to
  // read. Like the panel width, it belongs to this window's layout.
  ForumPanel? _minimized;

  static ForumPanel _other(ForumPanel panel) =>
      panel == ForumPanel.main ? ForumPanel.secondary : ForumPanel.main;

  void _minimize(ForumPanel panel) {
    final shell = ShellScope.read(context);
    final visible = shell.selectedTabIn(_other(panel));
    if (visible == null) return;
    // Keyboard input and sidebar navigation follow the active tab, so it
    // cannot stay behind in a panel that is no longer shown.
    if (shell.activeTab?.panel == panel) shell.selectTab(visible.id);
    setState(() => _minimized = panel);
  }

  // Restoring a panel leaves input where it is, so a reply being written
  // beside it keeps its place; picking one of the panel's tabs moves it.
  void _restore(ForumPanel panel, {String? tabId, bool newTab = false}) {
    final shell = ShellScope.read(context);
    setState(() => _minimized = null);
    if (newTab) {
      shell.createTab(panel: panel);
    } else if (tabId != null) {
      shell.selectTab(tabId);
    }
  }

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
    // Whatever becomes active in a minimized panel, whether a topic opened
    // from the list, a link or another forum's workspace, is what the reader
    // asked to see, so the panel comes back to show it.
    if (_minimized case final panel? when shell.activeTab?.panel == panel) {
      _minimized = null;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 640 + workspacePanelGap;
        shell.topicPanelsVisible = horizontal;
        Widget panel(ForumPanel panel, {Widget? action}) {
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
            action: action,
          );
        }

        if (!horizontal) {
          final active = shell.activeTab?.panel ?? ForumPanel.main;
          return Column(
            children: [
              ForumTabScope(
                tabId: shell.selectedTabIn(active)?.id,
                panel: active,
                child: TopicPanelTabs(panel: active),
              ),
              Expanded(
                child: Stack(
                  children: [
                    for (final target in ForumPanel.values)
                      Positioned.fill(
                        child: Offstage(
                          offstage: active != target,
                          child: TickerMode(
                            enabled: active == target,
                            child: ExcludeFocus(
                              excluding: active != target,
                              child: panel(target),
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

        Widget minimize(ForumPanel target) {
          final available = shell.selectedTabIn(_other(target)) != null;
          return DButton.iconOnly(
            key: ValueKey('minimize-panel-${target.name}'),
            icon: const DIcon(DIcons.downLeftAndUpRightToCenter),
            tooltip: available
                ? 'Minimize panel'
                : 'Open a tab in the other panel first',
            variant: DButtonVariant.transparentBackground,
            onPressed: available ? () => _minimize(target) : null,
          );
        }

        final maximumMainWidth = constraints.maxWidth - 320;
        final minimized = _minimized;
        if (minimized == null) {
          return Row(
            children: [
              ResizablePane(
                controller: _mainWidth,
                edge: ResizablePaneEdge.trailing,
                resizeKey: 'main-panel',
                semanticsLabel: 'Resize main panel',
                maximumWidth: maximumMainWidth,
                gap: workspacePanelGap,
                handleWidth: workspacePanelGap,
                child: panel(
                  ForumPanel.main,
                  action: minimize(ForumPanel.main),
                ),
              ),
              Expanded(
                child: panel(
                  ForumPanel.secondary,
                  action: minimize(ForumPanel.secondary),
                ),
              ),
            ],
          );
        }

        final shown = _other(minimized);
        final mainWidth = _mainWidth.effectiveWidth(maximum: maximumMainWidth);
        final dock = SizedBox(
          width: PanelRail.width,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The minimized panel stays mounted at the width it returns
              // to, so restoring it shows the same reader, list and scroll
              // position instead of building them again.
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: minimized == ForumPanel.main
                    ? mainWidth - workspacePanelGap
                    : constraints.maxWidth - mainWidth,
                child: Offstage(
                  child: TickerMode(
                    enabled: false,
                    child: ExcludeFocus(child: panel(minimized)),
                  ),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.topStart,
                child: CurrentForumTabsRail(
                  key: ValueKey('panel-rail-${minimized.name}'),
                  panel: minimized,
                  semanticLabel: minimized == ForumPanel.main
                      ? 'Main panel, minimized'
                      : 'Secondary panel, minimized',
                  opensTowardStart: minimized == ForumPanel.secondary,
                  onRestore: () => _restore(minimized),
                  onSelect: (id) => _restore(minimized, tabId: id),
                  onNewTab: () => _restore(minimized, newTab: true),
                ),
              ),
            ],
          ),
        );
        return Row(
          children: [
            if (minimized == ForumPanel.main) ...[
              dock,
              const SizedBox(width: workspacePanelGap),
            ],
            Expanded(child: panel(shown, action: minimize(shown))),
            if (minimized == ForumPanel.secondary) ...[
              const SizedBox(width: workspacePanelGap),
              dock,
            ],
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
    this.action,
  });

  final bool showHeader;
  final MainContent? content;
  final ForumPanel panel;
  final ForumTab? tab;
  final Widget? action;

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
                  trailing: action,
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
