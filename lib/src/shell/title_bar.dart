import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../plugin_api/plugin_scope.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'composer/presentation.dart';
import 'desktop_panels.dart';
import 'forum_search.dart';
import 'forum_theme_surfaces.dart';
import 'message_archive_button.dart';
import 'message_create_button.dart';
import 'shell_scope.dart';
import 'topic_create_button.dart';
import 'user_menu_button.dart';

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

  final bool showControls;

  /// Clearance already supplied by the rail and docked sidebar.
  final double? leadingInset;
  final DesktopPanelsLayout? panelsLayout;

  // Desktop mockup chrome row, including its vertical control insets.
  static const double height = 49;
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
      height,
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final searchSize = DControlStyle.isTouch(context)
              ? DControlSize.large
              : DControlSize.field;
          final rowHeight = showControls ? _rowHeight(context) : height;
          // Large-text count capsules keep their full labels. At narrow desktop
          // widths, give account actions a second row below the window controls.
          final stacked =
              showControls &&
              (constraints.maxWidth < 560 ||
                  (constraints.maxWidth < 760 &&
                      MediaQuery.textScalerOf(context).scale(12) > 18));
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
            height: stacked
                ? rowHeight * (1 + _actionRows(context, constraints.maxWidth))
                : rowHeight,
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
                                    width:
                                        leadingInset ??
                                        (hasWindowChrome ? 94 : 8),
                                  ),
                                  search,
                                  const SizedBox(width: trailingInset),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(
                            height:
                                rowHeight *
                                _actionRows(context, constraints.maxWidth),
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
                              width: leadingInset ?? (hasWindowChrome ? 94 : 8),
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

  @override
  Widget build(BuildContext context) => ShellSelector<Object>(
    select: (shell) => (
      shell.forumActive,
      shell.currentContent,
      shell.canReplyHere,
      shell.canCreateTopicFromList,
      shell.canCreateTopicFromSidebar,
      shell.currentInstance?.isConnected,
      shell.currentInstance?.user?.canSendPrivateMessages,
    ),
    builder: (context, _, _) => _action(context),
  );

  Widget _action(BuildContext context) {
    final shell = ShellScope.maybeOf(context);
    if (shell == null ||
        !shell.forumActive ||
        ComposerPresentationHost.hasVisibleComposerOf(context)) {
      return const SizedBox.shrink();
    }
    final route = shell.currentContent;
    Widget? action;
    if (route?.isTopic == true) {
      if (shell.canReplyHere) {
        action = DButton(
          key: const ValueKey('title-bar-reply'),
          label: const DIcon(DIcons.reply, size: 14),
          tooltip: context.l10n.reply,
          semanticLabel: context.l10n.reply,
          variant: DButtonVariant.primary,
          shape: DButtonShape.pill,
          size: DControlStyle.isTouch(context)
              ? DButtonSize.action
              : DButtonSize.chrome,
          density: DControlStyle.isTouch(context)
              ? DButtonDensity.standard
              : DButtonDensity.chrome,
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
      action = TopicCreateButton(
        onPressed: () => unawaited(
          shell.canCreateTopicFromList
              ? shell.openNewTopicFromList()
              : shell.openNewTopicFromSidebar(),
        ),
        alwaysShowDrafts: true,
        primaryAction: DButton(
          key: TopicCreateButton.buttonKey,
          label: const DIcon(DIcons.penToSquare, size: 14),
          tooltip: context.l10n.newTopic,
          semanticLabel: context.l10n.newTopic,
          shape: DButtonShape.pill,
          variant: DButtonVariant.primary,
          size: DControlStyle.isTouch(context)
              ? DButtonSize.action
              : DButtonSize.chrome,
          density: DControlStyle.isTouch(context)
              ? DButtonDensity.standard
              : DButtonDensity.chrome,
          onPressed: () => unawaited(
            shell.canCreateTopicFromList
                ? shell.openNewTopicFromList()
                : shell.openNewTopicFromSidebar(),
          ),
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
}
