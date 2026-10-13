import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'src/models/forum_background.dart';
import 'src/shell/forum_theme_surfaces.dart';
import 'src/shell/shell_panel.dart';
import 'src/theme/app_theme.dart';
import 'src/theme/d_icons.dart';

/// Account-free native fixture for workspace panel material and composition.
/// WORKSPACE_REVIEW_CAPTURE=true saves a light/dark opacity matrix in /tmp.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WorkspacePanelReview());
}

class WorkspacePanelReview extends StatefulWidget {
  const WorkspacePanelReview({super.key});
  @override
  State<WorkspacePanelReview> createState() => _WorkspacePanelReviewState();
}

class _WorkspacePanelReviewState extends State<WorkspacePanelReview> {
  final _capture = GlobalKey();
  bool _dark = true;
  bool _split = false;
  double _transparency = 0;
  DAppearanceMaterial _material = DAppearanceMaterial.liquidGlass;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_review()));
  }

  Future<void> _review() async {
    if (Platform.isMacOS) {
      await const MethodChannel(
        'org.discourse.native/window',
      ).invokeMethod<void>('dismissLaunchScreen');
    }
    if (!const bool.fromEnvironment('WORKSPACE_REVIEW_CAPTURE')) return;
    for (final dark in [true, false]) {
      for (final material in DAppearanceMaterial.values) {
        for (final transparency in [0.0, .3]) {
          setState(() {
            _dark = dark;
            _material = material;
            _transparency = transparency;
            _split = transparency > 0;
          });
          await Future<void>.delayed(const Duration(milliseconds: 650));
          await WidgetsBinding.instance.endOfFrame;
          final boundary =
              _capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          boundary.markNeedsPaint();
          WidgetsBinding.instance.scheduleFrame();
          await WidgetsBinding.instance.endOfFrame;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final path =
              '${Directory.systemTemp.path}/discourse-workspace-'
              '${dark ? 'dark' : 'light'}-${material.name}-'
              '${transparency > 0 ? 'translucent-split' : 'opaque'}.png';
          await File(path).writeAsBytes(bytes!.buffer.asUint8List());
          debugPrint('WORKSPACE_CAPTURE $path');
        }
      }
    }
  }

  Widget _panel(String title, {bool reader = false}) => WorkspacePanel(
    child: DPageSurface(
      framed: false,
      tabs: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            DButton.iconOnly(
              icon: const DIcon(DIcons.chevronDown),
              onPressed: () {},
              tooltip: 'Tabs',
              semanticLabel: 'Tabs',
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 180,
              child: DDocumentTab(
                selected: true,
                onSelect: () {},
                onClose: () {},
                closeLabel: 'Close $title',
                child: Text(title),
              ),
            ),
            const Spacer(),
            DButton.iconOnly(
              icon: DLayoutGlyph(
                mainVisible: true,
                secondaryVisible: _split,
                changingPanel: 1,
              ),
              onPressed: () => setState(() => _split = !_split),
              tooltip: 'Split view',
              semanticLabel: 'Split view',
            ),
          ],
        ),
      ),
      child: reader
          ? const Padding(
              padding: EdgeInsets.all(36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('A topic in the community'),
                  SizedBox(height: 32),
                  Text(
                    'A single reading surface lets the window canvas show '
                    'through consistently below the document tabs.',
                  ),
                  SizedBox(height: 32),
                  DSeparator(),
                  SizedBox(height: 32),
                  Text('More topics'),
                ],
              ),
            )
          : Center(
              child: Wrap(
                spacing: 36,
                runSpacing: 36,
                alignment: WrapAlignment.center,
                children: [
                  for (final label in [
                    'Activity',
                    'Bookmarks',
                    'Categories',
                    'Chat',
                    'Drafts',
                    'Groups',
                    'Topics',
                    'Settings',
                  ])
                    SizedBox(
                      width: 100,
                      child: DButton(label: Text(label), onPressed: () {}),
                    ),
                ],
              ),
            ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final base = AppTheme.forBrightness(
      _dark ? Brightness.dark : Brightness.light,
      background: ForumBackground.appearance(transparency: _transparency),
    );
    // Reference screenshot palette, isolated from account or server settings.
    final colors = base.colorScheme.copyWith(
      surface: _dark ? const Color(0xff2d303b) : const Color(0xfff4f4f7),
      onSurface: _dark ? const Color(0xffeeeeef) : const Color(0xff242631),
      primary: const Color(0xffbd93f9),
    );
    final tokens = base.extension<DTokens>()!;
    final theme = DMaterialTheme.apply(
      base.copyWith(
        colorScheme: colors,
        extensions: [
          ...base.extensions.values,
          tokens.copyWith(colors: colors, background: colors.surface),
        ],
      ),
      _material,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeAnimationStyle: AnimationStyle.noAnimation,
      theme: theme,
      home: Center(
        child: RepaintBoundary(
          key: _capture,
          child: SizedBox(
            width: 1000,
            height: 680,
            child: ForumWindowBackground(
              child: ShellWorkspace(
                atWindowEdge: false,
                child: Row(
                  children: [
                    Expanded(child: _panel('Start page')),
                    if (_split) ...[
                      const SizedBox(width: 6),
                      Expanded(child: _panel('Topic', reader: true)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
