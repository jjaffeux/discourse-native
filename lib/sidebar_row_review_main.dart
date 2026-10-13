import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'src/theme/app_theme.dart';
import 'src/theme/d_icons.dart';

/// Account-free native capture of sidebar row states in both appearances.
/// Run with --dart-define=SIDEBAR_ROW_REVIEW_CAPTURE=true to export to /tmp.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _SidebarRowReview());
}

class _SidebarRowReview extends StatefulWidget {
  const _SidebarRowReview();
  @override
  State<_SidebarRowReview> createState() => _SidebarRowReviewState();
}

class _SidebarRowReviewState extends State<_SidebarRowReview> {
  final _capture = GlobalKey();
  final _hoverTargets = List.generate(4, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_review()));
  }

  Future<void> _save(String name) async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    boundary.markNeedsPaint();
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File(
      '${Directory.systemTemp.path}/discourse-sidebar-rows-$name.png',
    );
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('SIDEBAR_ROW_CAPTURE ${file.path}');
  }

  Future<void> _review() async {
    if (Platform.isMacOS) {
      await const MethodChannel(
        'org.discourse.native/window',
      ).invokeMethod<void>('dismissLaunchScreen');
    }
    if (!const bool.fromEnvironment('SIDEBAR_ROW_REVIEW_CAPTURE')) return;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await _save('rest');
    for (var index = 0; index < _hoverTargets.length; index++) {
      final target =
          _hoverTargets[index].currentContext!.findRenderObject()! as RenderBox;
      final position = target.localToGlobal(target.size.center(Offset.zero));
      GestureBinding.instance.handlePointerEvent(
        PointerAddedEvent(
          kind: PointerDeviceKind.mouse,
          device: 77,
          position: position,
        ),
      );
      GestureBinding.instance.handlePointerEvent(
        PointerHoverEvent(
          kind: PointerDeviceKind.mouse,
          device: 77,
          position: position,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await _save('hover-$index');
      GestureBinding.instance.handlePointerEvent(
        const PointerRemovedEvent(kind: PointerDeviceKind.mouse, device: 77),
      );
    }
    debugPrint('SIDEBAR_ROW_REVIEW_COMPLETE');
  }

  Widget _conversation(String title, {bool selected = false, Key? key}) =>
      DItem(
        key: key,
        size: DItemSize.sm,
        shape: DItemShape.menu,
        selected: selected,
        selectionStyle: DItemSelectionStyle.sidebar,
        showSelectionIndicator: false,
        onPressed: () {},
        children: [
          const DItemMedia(
            variant: DItemMediaVariant.avatar,
            child: DAvatar(
              dimension: 32,
              decorative: true,
              fallback: DAvatarFallback(child: DIcon(DIcons.hashtag)),
            ),
          ),
          DItemContent(
            children: [
              DItemTitle(child: Text(title)),
              const DItemDescription(child: Text('Alex: See you tomorrow')),
            ],
          ),
        ],
      );

  Widget _panel(int index, bool dark, DAppearanceMaterial material) {
    final theme = DMaterialTheme.apply(
      dark ? AppTheme.dark : AppTheme.light,
      material,
    );
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final tokens = DTokens.of(context);
          return ColoredBox(
            color: Color.lerp(tokens.background, tokens.foreground, .045)!,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${dark ? 'Dark' : 'Light'} · ${material == DAppearanceMaterial.liquidGlass ? 'Glass' : 'Standard'}',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 16),
                  DSidebarMenuButton(
                    variant: DSidebarMenuButtonVariant.navigation,
                    isActive: true,
                    icon: const DIcon(DIcons.comment),
                    onPressed: () {},
                    child: const Text('Topics'),
                  ),
                  DSidebarMenuButton(
                    variant: DSidebarMenuButtonVariant.navigation,
                    icon: const DIcon(DIcons.user),
                    onPressed: () {},
                    child: const Text('Users'),
                  ),
                  const SizedBox(height: 20),
                  const DSidebarGroupLabel(child: Text('Categories')),
                  DSidebarMenuButton(
                    isActive: true,
                    icon: const DIcon(DIcons.hashtag),
                    onPressed: () {},
                    child: const Text('Baking'),
                  ),
                  DSidebarMenuButton(
                    icon: const DIcon(DIcons.hashtag),
                    onPressed: () {},
                    child: const Text('Photography'),
                  ),
                  const SizedBox(height: 20),
                  const DSidebarGroupLabel(child: Text('Conversations')),
                  _conversation('General', selected: true),
                  const SizedBox(height: 4),
                  _conversation('Other channel', key: _hoverTargets[index]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: ColoredBox(
        color: const Color(0xff181a20),
        child: Center(
          child: FittedBox(
            child: RepaintBoundary(
              key: _capture,
              child: SizedBox(
                width: 1000,
                height: 470,
                child: Row(
                  spacing: 12,
                  children: [
                    for (final (index, state) in [
                      (false, DAppearanceMaterial.standard),
                      (true, DAppearanceMaterial.standard),
                      (false, DAppearanceMaterial.liquidGlass),
                      (true, DAppearanceMaterial.liquidGlass),
                    ].indexed)
                      Expanded(child: _panel(index, state.$1, state.$2)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
