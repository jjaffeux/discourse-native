import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'src/theme/app_theme.dart';
import 'src/theme/d_icons.dart';
import 'src/theme/d_native_icons.dart';

/// Account-free native rendering fixture for the sidebar mode switch.
/// SIDEBAR_REVIEW_CAPTURE=true saves the matrix and transition frames in /tmp.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SidebarSwitchReview());
}

class SidebarSwitchReview extends StatefulWidget {
  const SidebarSwitchReview({super.key});
  @override
  State<SidebarSwitchReview> createState() => _SidebarSwitchReviewState();
}

class _SidebarSwitchReviewState extends State<SidebarSwitchReview> {
  final _capture = GlobalKey();
  String _selected = 'forum';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_review()));
  }

  Future<void> _save(String name) async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // Redraw the whole matrix before reading retained native layers.
    boundary.markNeedsPaint();
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File(
      '${Directory.systemTemp.path}/discourse-sidebar-switch-$name.png',
    );
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('SIDEBAR_CAPTURE ${file.path}');
  }

  Future<void> _review() async {
    if (Platform.isMacOS) {
      await const MethodChannel(
        'org.discourse.native/window',
      ).invokeMethod<void>('dismissLaunchScreen');
    }
    if (!const bool.fromEnvironment('SIDEBAR_REVIEW_CAPTURE')) return;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await _save('forum');
    setState(() => _selected = 'chat');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await _save('transition');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _save('chat');
    setState(() => _selected = 'shortcuts');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _save('shortcuts');
  }

  Widget _switch(String selected, {bool dot = false}) => SizedBox(
    width: 226,
    child: DTabs<String>.controlled(
      value: selected,
      onChanged: (value) => setState(() => _selected = value!),
      children: [
        DTabList<String>(
          expandSelected: true,
          children: [
            const DTabTrigger(
              value: 'forum',
              semanticLabel: 'Forum',
              icon: DIcon(DIcons.layerGroup),
              selectedLabelOnly: true,
              child: Text('Forum'),
            ),
            DTabTrigger(
              value: 'chat',
              semanticLabel: 'Chat',
              icon: const DIcon(DIcons.comment),
              selectedLabelOnly: true,
              trailing: dot
                  ? const DNotificationDot()
                  : Builder(
                      builder: (context) => Text(
                        '43',
                        style: TextStyle(
                          color: DTokens.of(context).success,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
              child: const Text('Chat'),
            ),
            const DTabTrigger(
              value: 'shortcuts',
              semanticLabel: 'Shortcuts',
              icon: DIcon(DNativeIcons.bolt),
              selectedLabelOnly: true,
              child: Text('Shortcuts'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _sample(Brightness brightness, DAppearanceMaterial material) => Theme(
    data: DMaterialTheme.apply(
      brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      material,
    ),
    child: Builder(
      builder: (context) => ColoredBox(
        color: DTokens.of(context).background,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${brightness.name} · ${material.name}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              _switch(_selected),
              const SizedBox(height: 14),
              _switch(_selected, dot: true),
              const SizedBox(height: 14),
              MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: _switch(_selected),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark,
    home: Scaffold(
      body: Center(
        child: RepaintBoundary(
          key: _capture,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sample(Brightness.dark, DAppearanceMaterial.standard),
                  _sample(Brightness.dark, DAppearanceMaterial.liquidGlass),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sample(Brightness.light, DAppearanceMaterial.standard),
                  _sample(Brightness.light, DAppearanceMaterial.liquidGlass),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
