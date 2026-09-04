import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../plugin_api/plugin_scope.dart';
import '../plugin_api/site_plugin_api.dart';
import 'forum_search.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'user_menu_button.dart';

class ShellTitleBar extends StatelessWidget {
  const ShellTitleBar({super.key, this.showControls = true});

  static const _windowChannel = MethodChannel('org.discourse.native/window');

  @visibleForTesting
  static const maximizeGestureKey = ValueKey('shell-title-bar-maximize');

  final bool showControls;

  static const double height = 48;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool get columnsCarryUserMenu => !isSupported;

  static void _toggleMaximized() {
    unawaited(_windowChannel.invokeMethod<void>('toggleMaximized'));
  }

  @override
  Widget build(BuildContext context) {
    if (!isSupported) return const SizedBox.shrink();

    final surface = Theme.of(context).scaffoldBackgroundColor;

    return SizedBox(
      height: height,
      child: ColoredBox(
        color: surface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              key: maximizeGestureKey,
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _toggleMaximized,
              child: const SizedBox.expand(),
            ),
            if (showControls)
              Row(
                children: [
                  const SizedBox(width: 88),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: ShellSelector<ShellRootMode>(
                          select: (controller) => controller.rootMode,
                          builder: (context, rootMode, _) => switch (rootMode) {
                            ShellRootMode.forum => const ForumSearch(
                              dense: true,
                            ),
                            ShellRootMode.aggregate => const SizedBox.shrink(),
                          },
                        ),
                      ),
                    ),
                  ),
                  ...PluginScope.of(context).registry.shellHeaderActions(
                    context,
                    surface: PluginHeaderSurface.titleBar,
                    compact: false,
                    ringColor: surface,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: UserMenuButton(size: 26, ringColor: surface),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
