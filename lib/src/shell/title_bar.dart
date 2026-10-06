import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../plugin_api/plugin_scope.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import '../theme/d_native_icons.dart';
import 'composer_presentation.dart';
import 'desktop_panels.dart';
import 'forum_search.dart';
import 'forum_theme_surfaces.dart';
import 'message_archive_button.dart';
import 'message_create_button.dart';
import 'shell_scope.dart';
import 'topic_create_button.dart';
import 'user_menu_button.dart';

class ShellTitleBar extends StatelessWidget {
  const ShellTitleBar({super.key, this.showControls = true, this.panelsLayout});

  static const _windowChannel = MethodChannel('org.discourse.native/window');

  @visibleForTesting
  static const maximizeGestureKey = ValueKey('shell-title-bar-maximize');

  final bool showControls;
  final DesktopPanelsLayout? panelsLayout;

  // Desktop mockup chrome row, including its vertical control insets.
  static const double height = 53;

  // Every platform keeps account and search controls above the topic list.
  static bool get isSupported => true;

  static bool get _hasWindowChrome =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool get columnsCarryUserMenu => !isSupported;

  static void _toggleMaximized() {
    unawaited(_windowChannel.invokeMethod<void>('toggleMaximized'));
  }

  @override
  Widget build(BuildContext context) {
    if (!showControls && !_hasWindowChrome) return const SizedBox.shrink();

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
          // Retain the mockup's clearance as the field grows with text.
          final rowHeight =
              height +
              (showControls
                  ? DControlStyle.scaledHeight(
                          searchSize,
                          MediaQuery.textScalerOf(context),
                          context: context,
                        ) -
                        DControlStyle.height(searchSize, context: context)
                  : 0);
          // Large-text count capsules keep their full labels. At narrow desktop
          // widths, give account actions a second row below the window controls.
          final stacked =
              showControls &&
              (constraints.maxWidth < 700 ||
                  (constraints.maxWidth < 1000 &&
                      MediaQuery.textScalerOf(context).scale(12) > 18));
          final search = Expanded(
            child: ForumSearch(dense: true, size: searchSize),
          );
          final actions = <Widget>[
            if (showControls) const _DesktopPrimaryAction(),
            if (showControls && panelsLayout != null)
              ListenableBuilder(
                listenable: panelsLayout!,
                builder: (context, _) {
                  if (!panelsLayout!.canToggleSplit) {
                    return const SizedBox.shrink();
                  }
                  final label = panelsLayout!.splitVisible
                      ? context.l10n.hideSplitView
                      : context.l10n.showSplitView;
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(
                      end: DSpacing.controlGap,
                    ),
                    child: DTooltip(
                      message: label,
                      child: DToggle.iconOnly(
                        key: const ValueKey('title-bar-split-view'),
                        icon: const DIcon(DNativeIcons.columns),
                        semanticLabel: label,
                        size: DToggleSize.action,
                        pressed: panelsLayout!.splitVisible,
                        onPressedChanged: (_) => panelsLayout!.toggleSplit(),
                      ),
                    ),
                  );
                },
              ),
            if (showControls)
              ...PluginScope.of(context).registry.shellHeaderActions(
                context,
                surface: PluginHeaderSurface.titleBar,
                compact: stacked,
                ringColor: surface,
              ),
            if (showControls)
              Padding(
                padding: EdgeInsetsDirectional.only(
                  end: stacked ? DSpacing.xs : DSpacing.sm,
                ),
                child: UserMenuButton(ringColor: surface),
              ),
          ];
          return SizedBox(
            height: stacked ? rowHeight * 2 : rowHeight,
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
                  if (_hasWindowChrome)
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
                            child: Row(
                              children: [
                                SizedBox(width: _hasWindowChrome ? 88 : 8),
                                search,
                                const SizedBox(width: 8),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: rowHeight,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: actions,
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          SizedBox(width: _hasWindowChrome ? 88 : 8),
                          search,
                          const SizedBox(width: DSpacing.controlGap),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: actions,
                          ),
                        ],
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
  Widget build(BuildContext context) {
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
          icon: const DIcon(DIcons.reply),
          label: Text(context.l10n.reply),
          variant: DButtonVariant.primary,
          shape: DButtonShape.pill,
          size: DButtonSize.action,
          onPressed: shell.openReply,
        );
      }
    } else if (route?.isMessages == true) {
      action = const MessageCreateButton(showLabel: true, pill: true);
    } else if (shell.canCreateTopicFromSidebar) {
      action = TopicCreateButton(
        onPressed: () => unawaited(shell.openNewTopicFromSidebar()),
      );
    }
    final topic = shell.currentTopic;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DSpacing.controlGap,
      children: [
        ?action,
        if (route?.isTopic == true &&
            topic?.privateMessage == true &&
            shell.currentInstance?.user?.canSendPrivateMessages == true)
          MessageArchiveButton(
            siteUrl: shell.currentInstance!.url,
            topic: topic!,
          ),
        if (action != null) const SizedBox(width: DSpacing.controlGap),
      ],
    );
  }
}
