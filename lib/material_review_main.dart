import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import 'src/models/forum_background.dart';
import 'src/shell/forum_theme_surfaces.dart';
import 'src/theme/app_theme.dart';

/// Focused native rendering/performance fixture. It uses no accounts or APIs.
/// Run with --dart-define=MATERIAL_REVIEW_CAPTURE=true to save evidence in /tmp.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialReview());
}

class MaterialReview extends StatefulWidget {
  const MaterialReview({super.key});
  @override
  State<MaterialReview> createState() => _MaterialReviewState();
}

class _MaterialReviewState extends State<MaterialReview> {
  final _capture = GlobalKey();
  final _scroll = ScrollController();
  final _frames = <ui.FrameTiming>[];
  DAppearanceMaterial _material = DAppearanceMaterial.liquidGlass;
  Brightness _brightness = Brightness.dark;
  bool _mobile = false;
  double _textScale = 1;
  bool _measuring = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(_timings);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_review()));
  }

  void _timings(List<ui.FrameTiming> values) {
    if (_measuring) _frames.addAll(values);
  }

  Future<void> _review() async {
    if (Platform.isMacOS) {
      await const MethodChannel(
        'org.discourse.native/window',
      ).invokeMethod<void>('dismissLaunchScreen');
    }
    await LiquidGlassShaders.ensureLoaded();
    debugPrint(
      'MATERIAL_ENGINE ${jsonEncode({'platform': Platform.operatingSystem, 'shaderBackdrop': ui.ImageFilter.isShaderFilterSupported, 'shadersLoaded': LiquidGlassShaders.isLoaded})}',
    );
    if (!const bool.fromEnvironment('MATERIAL_REVIEW_CAPTURE')) return;
    for (final mode in DAppearanceMaterial.values) {
      for (final brightness in Brightness.values) {
        for (final mobile in [false, true]) {
          if (!mounted) return;
          setState(() {
            _material = mode;
            _brightness = brightness;
            _mobile = mobile;
            _textScale = mobile ? 2 : 1;
          });
          await Future<void>.delayed(const Duration(milliseconds: 800));
          if (_scroll.hasClients) _scroll.jumpTo(0);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final boundary =
              _capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final file = File(
            '${Directory.systemTemp.path}/discourse-material-${Platform.operatingSystem}-${mode.name}-${brightness.name}-${mobile ? 'mobile2x' : 'desktop'}.png',
          );
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          debugPrint('MATERIAL_CAPTURE ${file.path}');
          if (mobile) continue;
          _frames.clear();
          _measuring = true;
          for (var repeat = 0; repeat < 3; repeat++) {
            if (!_scroll.hasClients) break;
            await _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 1000),
              curve: Curves.linear,
            );
            await _scroll.animateTo(
              0,
              duration: const Duration(milliseconds: 1000),
              curve: Curves.linear,
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
          _measuring = false;
          List<double> values(double Function(ui.FrameTiming) read) =>
              _frames.map(read).toList()..sort();
          final raster = values((f) => f.rasterDuration.inMicroseconds / 1000);
          final build = values((f) => f.buildDuration.inMicroseconds / 1000);
          double percentile(List<double> v, double q) =>
              v.isEmpty ? 0 : v[((v.length - 1) * q).round()];
          debugPrint(
            'MATERIAL_PERF ${jsonEncode({'material': mode.name, 'brightness': brightness.name, 'frames': _frames.length, 'rasterP50ms': percentile(raster, .5), 'rasterP95ms': percentile(raster, .95), 'rasterMaxms': percentile(raster, 1), 'buildP95ms': percentile(build, .95)})}',
          );
        }
      }
    }
    if (mounted) {
      setState(() {
        _material = DAppearanceMaterial.liquidGlass;
        _brightness = Brightness.dark;
        _mobile = false;
        _textScale = 1;
      });
    }
    debugPrint('MATERIAL_REVIEW_COMPLETE');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeTimingsCallback(_timings);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Native material review',
    debugShowCheckedModeBanner: false,
    themeAnimationStyle: AnimationStyle.noAnimation,
    theme: DMaterialTheme.apply(
      AppTheme.forBrightness(
        _brightness,
        background: const ForumBackground.appearance(
          transparency: .3,
          effect: ForumBackgroundEffect.hatch,
        ),
      ),
      _material,
    ),
    home: DMaterialAccessibility(
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(_textScale)),
        child: RepaintBoundary(
          key: _capture,
          child: ForumWindowBackground(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                child: Column(
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        DToggleGroup<DAppearanceMaterial>(
                          values: [_material],
                          allowEmptySelection: false,
                          inset: true,
                          items: const [
                            DToggleGroupItem(
                              value: DAppearanceMaterial.standard,
                              child: Text('Standard'),
                            ),
                            DToggleGroupItem(
                              value: DAppearanceMaterial.liquidGlass,
                              child: Text('Liquid glass'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _material = v.single),
                        ),
                        DToggle(
                          pressed: _brightness == Brightness.dark,
                          onPressedChanged: (v) => setState(
                            () => _brightness = v
                                ? Brightness.dark
                                : Brightness.light,
                          ),
                          child: const Text('Dark'),
                        ),
                        DToggle(
                          pressed: _mobile,
                          onPressedChanged: (v) => setState(() {
                            _mobile = v;
                            _textScale = v ? 2 : 1;
                          }),
                          child: const Text('Mobile 2x'),
                        ),
                        DDropdownMenu(
                          onOpenChange: (open, reason) =>
                              debugPrint('MATERIAL_MENU $open ${reason.name}'),
                          content: DDropdownMenuContent(
                            children: [
                              DDropdownMenuItem(
                                onPressed: () {},
                                child: const Text('Readable frosted menu'),
                              ),
                              DDropdownMenuItem(
                                onPressed: () {},
                                child: const Text('Native focus and targets'),
                              ),
                            ],
                          ),
                          child: DDropdownMenuTrigger.button(
                            label: const Text('Menu'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: _mobile ? 390 : 1100,
                          child: Builder(
                            builder: (context) => DPageSurface(
                              backgroundColor: ForumWindowBackground.panelColor(
                                context,
                              ),

                              header: const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('Native surface rendering'),
                              ),
                              child: ListView(
                                controller: _scroll,
                                padding: const EdgeInsets.all(16),
                                children: [
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      DButton(
                                        label: const Text('Primary action'),
                                        onPressed: () {},
                                      ),
                                      DButton(
                                        label: const Text('Raised control'),
                                        variant: DButtonVariant.outline,
                                        onPressed: () {},
                                      ),
                                      const DButton(
                                        label: Text('Disabled'),
                                        onPressed: null,
                                      ),
                                      DButton(
                                        label: const Text('Delete'),
                                        variant: DButtonVariant.destructive,
                                        onPressed: () {},
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  DInput(hintText: 'Recessed input'),
                                  const SizedBox(height: 16),
                                  DToggleGroup<int>(
                                    values: const [1],
                                    allowEmptySelection: false,
                                    inset: true,
                                    expanded: true,
                                    items: const [
                                      DToggleGroupItem(
                                        value: 1,
                                        child: Text('Selected'),
                                      ),
                                      DToggleGroupItem(
                                        value: 2,
                                        child: Text('Choice'),
                                      ),
                                    ],
                                    onChanged: (_) {},
                                  ),
                                  const SizedBox(height: 16),
                                  const DPopoverContent(
                                    child: Text(
                                      'Menus hold a deeper frost so their text stays readable.',
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  for (var row = 0; row < 24; row++)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: DCard(
                                        size: DCardSize.small,
                                        children: [
                                          DCardContent(
                                            child: Text(
                                              'Surface ${row + 1} · Scrolling keeps every control in its visible bounds.',
                                            ),
                                          ),
                                          DCardContent(
                                            child: Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                DButton(
                                                  label: const Text('Reply'),
                                                  onPressed: () {},
                                                ),
                                                DButton(
                                                  label: const Text('Save'),
                                                  variant:
                                                      DButtonVariant.outline,
                                                  onPressed: () {},
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
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
