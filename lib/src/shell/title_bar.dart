import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/icons/d_icons.dart';
import '../plugin_api/plugin_scope.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import 'composer/presentation_scope.dart';
import 'desktop_panels_layout.dart';
import 'forum_search.dart';
import 'forum_theme_surfaces.dart';
import 'message_archive_button.dart';
import 'message_create_button.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'topic_create_button.dart';
import 'user_menu_button.dart';

typedef _TitleBarLayout = ({bool stacked, int actionRows});

class ShellTitleBar extends StatelessWidget {
  const ShellTitleBar({
    super.key,
    this.showControls = true,
    this.panelsLayout,
    this.leadingInset,
  });

  static const _windowChannel = MethodChannel('org.discourse.native/window');

  @visibleForTesting
  static const maximizeGestureKey = ValueKey('shell-title-bar-maximize');

  @visibleForTesting
  static const composerToggleKey = ValueKey('title-bar-composer-toggle');

  final bool showControls;

  /// Clearance already supplied by the rail and docked sidebar.
  final double? leadingInset;
  final DesktopPanelsLayout? panelsLayout;

  /// How far the search field starts when nothing else clears the window's
  /// controls.
  static double get defaultLeadingInset => hasWindowChrome ? 94 : 8;

  static const double controlGap = 10;
  static const double trailingInset = 14;
  static const _rowPadding = EdgeInsets.only(top: 8, bottom: 4);

  // Every platform keeps account and search controls above the topic list.
  static bool get isSupported => true;

  static bool get hasWindowChrome =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool get columnsCarryUserMenu => !isSupported;

  static double heightFor(BuildContext context, double width) {
    final rowHeight = _rowHeight(context);
    final stacked =
        width < 560 ||
        (width < 760 && MediaQuery.textScalerOf(context).scale(12) > 18);
    return stacked ? rowHeight * (1 + _actionRows(context, width)) : rowHeight;
  }

  static int _actionRows(BuildContext context, double width) =>
      width < 440 && MediaQuery.textScalerOf(context).scale(12) > 18 ? 2 : 1;

  static double _rowHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final searchSize = DControlStyle.isTouch(context)
        ? DControlSize.large
        : DControlSize.field;
    final searchHeight =
        DControlStyle.scaledHeight(searchSize, scaler, context: context) +
        (searchSize == DControlSize.field ? .5 : 0);
    final avatarHeight = 36 * math.max(1, scaler.scale(14) / 14);
    return math.max(
      shellTitleBarHeight,
      math.max(searchHeight, avatarHeight) + _rowPadding.vertical,
    );
  }

  static void _toggleMaximized() {
    unawaited(_windowChannel.invokeMethod<void>('toggleMaximized'));
  }

  @override
  Widget build(BuildContext context) {
    if (!showControls && !hasWindowChrome) return const SizedBox.shrink();

    final surface = ForumWindowBackground.chromeColor(
      context,
      Theme.of(context).scaffoldBackgroundColor,
    );

    return SafeArea(
      bottom: false,
      child: DLayoutSelector<_TitleBarLayout>(
        select: (context, constraints) {
          // Large-text count capsules keep their full labels. At narrow desktop
          // widths, give account actions a second row below the window controls.
          final stacked =
              showControls &&
              (constraints.maxWidth < 560 ||
                  (constraints.maxWidth < 760 &&
                      MediaQuery.textScalerOf(context).scale(12) > 18));
          return (
            stacked: stacked,
            actionRows: stacked
                ? _actionRows(context, constraints.maxWidth)
                : 1,
          );
        },
        builder: (context, layout) {
          final (:stacked, :actionRows) = layout;
          final searchSize = DControlStyle.isTouch(context)
              ? DControlSize.large
              : DControlSize.field;
          final rowHeight = showControls
              ? _rowHeight(context)
              : shellTitleBarHeight;
          final search = Expanded(
            child: ForumSearch(dense: true, size: searchSize),
          );
          final actions = <Widget>[
            if (showControls) const _DesktopPrimaryAction(),
            if (showControls)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: trailingInset),
                child: UserMenuButton(
                  presentation: UserMenuPresentation.notifications,
                  ringColor: surface,
                  leadingActions: PluginScope.of(context).registry
                      .shellHeaderActions(
                        context,
                        surface: PluginHeaderSurface.titleBar,
                        compact: stacked,
                        ringColor: surface,
                      ),
                ),
              ),
          ];
          return SizedBox(
            height: stacked ? rowHeight * (1 + actionRows) : rowHeight,
            child: ColoredBox(
              color:
                  Theme.of(
                        context,
                      ).extension<ForumThemeEffects>()?.windowGradient !=
                      null
                  ? Colors.transparent
                  : ForumWindowBackground.surfaceColor(context, surface),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasWindowChrome)
                    GestureDetector(
                      key: maximizeGestureKey,
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: _toggleMaximized,
                      child: const SizedBox.expand(),
                    ),
                  if (showControls)
                    if (stacked)
                      Column(
                        children: [
                          SizedBox(
                            height: rowHeight,
                            child: Padding(
                              padding: _rowPadding,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: leadingInset ?? defaultLeadingInset,
                                  ),
                                  search,
                                  const SizedBox(width: trailingInset),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(
                            height: rowHeight * actionRows,
                            width: double.infinity,
                            child: Padding(
                              padding: _rowPadding,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Wrap(
                                  alignment: WrapAlignment.end,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  runSpacing: controlGap,
                                  children: actions,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Padding(
                        padding: _rowPadding,
                        child: Row(
                          children: [
                            SizedBox(
                              width: leadingInset ?? defaultLeadingInset,
                            ),
                            search,
                            const SizedBox(width: controlGap),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: actions,
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DesktopPrimaryAction extends StatelessWidget {
  const _DesktopPrimaryAction();

  static const _replyKey = ValueKey('title-bar-reply');

  @override
  Widget build(BuildContext context) => ShellSelector<Object>(
    select: (shell) => (
      shell.forumActive,
      shell.currentContent,
      shell.canReplyHere,
      shell.canCreateTopicFromList,
      shell.canCreateTopicFromSidebar,
      shell.currentInstance?.url,
      shell.currentInstance?.isConnected,
      shell.currentInstance?.user?.canSendPrivateMessages,
      shell.currentTopic?.privateMessage == true ? shell.currentTopic : null,
    ),
    builder: (context, _, _) => _action(context),
  );

  Widget _action(BuildContext context) {
    final shell = ShellScope.read(context);
    if (!shell.forumActive) return const SizedBox.shrink();
    final route = shell.currentContent;
    final inTopic = route?.isTopic == true;
    final composerToggle = _composerToggle(context, inTopic: inTopic);
    Widget? action;
    if (inTopic) {
      if (composerToggle != null || shell.canReplyHere) {
        action =
            composerToggle ??
            _capsuleButton(
              context,
              key: _replyKey,
              icon: DIcons.reply,
              label: context.l10n.reply,
              onPressed: shell.openReply,
            );
        if (!DControlStyle.isTouch(context)) {
          action = IntrinsicWidth(
            child: DCard(
              variant: DCardVariant.primaryCapsule,
              size: DCardSize.small,
              border: false,
              child: action,
            ),
          );
        }
      }
    } else if (composerToggle != null) {
      action = TopicCreateButton(
        onPressed: () {},
        alwaysShowDrafts: true,
        primaryAction: composerToggle,
      );
    } else if (route?.isMessages == true) {
      if (shell.currentInstance?.isConnected == true &&
          shell.currentInstance?.user?.canSendPrivateMessages == true) {
        action = TopicCreateButton(
          onPressed: () {},
          alwaysShowDrafts: true,
          primaryAction: const MessageCreateButton(
            showLabel: false,
            pill: true,
          ),
        );
      }
    } else if (shell.canCreateTopicFromList ||
        shell.canCreateTopicFromSidebar) {
      void openNewTopic() => unawaited(
        shell.canCreateTopicFromList
            ? shell.openNewTopicFromList()
            : shell.openNewTopicFromSidebar(),
      );
      action = TopicCreateButton(
        onPressed: openNewTopic,
        alwaysShowDrafts: true,
        primaryAction: _capsuleButton(
          context,
          key: TopicCreateButton.buttonKey,
          icon: DIcons.penToSquare,
          label: context.l10n.newTopic,
          onPressed: openNewTopic,
        ),
      );
    }
    final topic = shell.currentTopic;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        end: action == null ? 0 : ShellTitleBar.controlGap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: ShellTitleBar.controlGap,
        children: [
          ?action,
          if (route?.isTopic == true &&
              topic?.privateMessage == true &&
              shell.currentInstance?.user?.canSendPrivateMessages == true)
            MessageArchiveButton(
              siteUrl: shell.currentInstance!.url,
              topic: topic!,
            ),
        ],
      ),
    );
  }

  /// The way to the draft on screen, which replaces the page's own action for
  /// as long as one is open. It answers for the forum's selected draft only.
  Widget? _composerToggle(BuildContext context, {required bool inTopic}) {
    final activity = ComposerActivityScope.of(context);
    if (activity == ComposerActivity.none) return null;
    final writing = activity == ComposerActivity.writing;
    return MergeSemantics(
      child: Semantics(
        toggled: writing,
        child: _capsuleButton(
          context,
          key: ShellTitleBar.composerToggleKey,
          icon: inTopic ? DIcons.reply : DIcons.penToSquare,
          heldIn: writing,
          label: writing
              ? context.l10n.minimizeComposer
              : context.l10n.resumeComposerEditing,
          onPressed: () => writing
              ? ComposerPresentationScope.minimizeComposer(context)
              : ComposerPresentationScope.restoreComposer(context),
        ),
      ),
    );
  }

  Widget _capsuleButton(
    BuildContext context, {
    required Key key,
    required DIconData icon,
    required String label,
    required VoidCallback onPressed,
    bool heldIn = false,
  }) {
    final touch = DControlStyle.isTouch(context);
    return DButton(
      key: key,
      expanded: heldIn,
      label: DIcon(icon, size: 14),
      tooltip: label,
      semanticLabel: label,
      variant: DButtonVariant.primary,
      shape: DButtonShape.pill,
      size: touch ? DButtonSize.action : DButtonSize.chrome,
      density: touch ? DButtonDensity.standard : DButtonDensity.chrome,
      onPressed: onPressed,
    );
  }
}
