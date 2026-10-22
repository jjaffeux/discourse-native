import 'dart:async';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/ui/foundation/native_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Payload = Map<Object?, Object?>;

class _Bridge {
  final uploads = <_Payload>[];
  final scenes = <_Payload>[];
  final pending = <Completer<void>>[];
  bool blocked = false;
  bool fail = false;
  int active = 0;
  int peak = 0;

  Future<Object?> call(MethodCall call) async {
    if (call.method == 'available') return true;
    if (call.method == 'scene') scenes.add(call.arguments as _Payload);
    if (call.method != 'image') return null;
    uploads.add(call.arguments as _Payload);
    active++;
    if (active > peak) peak = active;
    try {
      if (blocked) {
        final completion = Completer<void>();
        pending.add(completion);
        await completion.future;
      }
      if (fail) throw PlatformException(code: 'unavailable');
    } finally {
      active--;
    }
    return null;
  }

  void release() {
    blocked = false;
    for (final completion in pending) {
      if (!completion.isCompleted) completion.complete();
    }
  }
}

Widget _fixture(Widget Function(BuildContext) content, {double scale = 1}) =>
    MaterialApp(
      theme: DMaterialTheme.apply(
        AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        DAppearanceMaterial.liquidGlass,
      ),
      home: MediaQuery(
        data: MediaQueryData(devicePixelRatio: scale),
        child: Center(
          child: NativeGlassScope(child: Builder(builder: content)),
        ),
      ),
    );

Widget _artwork(BuildContext context, Color color, {Key? key}) =>
    NativeGlassContent(
      key: key,
      group: NativeGlass.of(context)!,
      child: SizedBox.square(dimension: 24, child: ColoredBox(color: color)),
    );

Future<void> _drain(WidgetTester tester, [int frames = 4]) async {
  for (var frame = 0; frame < frames; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }
}

Future<({int width, int height, List<int> rgba})> _pixels(
  WidgetTester tester,
  _Payload payload,
) async => (await tester.runAsync(() async {
  final codec = await ui.instantiateImageCodec(payload['png']! as Uint8List);
  final frame = await codec.getNextFrame();
  try {
    final bytes = await frame.image.toByteData();
    return (
      width: frame.image.width,
      height: frame.image.height,
      rgba: bytes!.buffer.asUint8List().toList(),
    );
  } finally {
    frame.image.dispose();
    codec.dispose();
  }
}))!;

void main() {
  late _Bridge bridge;

  setUp(() {
    bridge = _Bridge();
    NativeGlass.available.value = true;
    NativeGlass.disabled.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeGlass.channel, bridge.call);
  });

  tearDown(() {
    bridge.release();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeGlass.channel, null);
    NativeGlass.available.value = false;
    NativeGlass.disabled.value = false;
  });

  testWidgets('disposal retires an unfinished image capture', (tester) async {
    await tester.pumpWidget(
      _fixture((context) => _artwork(context, Colors.red)),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await _drain(tester);
    expect(bridge.uploads, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposal retires a blocked bridge acknowledgement', (
    tester,
  ) async {
    bridge.blocked = true;
    await tester.pumpWidget(
      _fixture((context) => _artwork(context, Colors.red)),
    );
    await _drain(tester);
    expect(bridge.uploads, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    final afterDisposal = bridge.scenes.length;
    bridge.release();
    await _drain(tester);
    expect(bridge.uploads, hasLength(1));
    expect(
      bridge.scenes
          .skip(afterDisposal)
          .where((scene) => scene['visible'] == true),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'retained reparenting waits for the old bridge and paints again',
    (tester) async {
      final key = GlobalKey();
      var right = false;
      Widget fixture() => _fixture((context) {
        final content = _artwork(context, const Color(0xff0000ff), key: key);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              key: const ValueKey('left'),
              width: 60,
              child: right ? null : content,
            ),
            SizedBox(
              key: const ValueKey('right'),
              width: 60,
              child: right ? content : null,
            ),
          ],
        );
      });

      bridge.blocked = true;
      await tester.pumpWidget(fixture());
      await _drain(tester);
      expect(bridge.uploads, hasLength(1));
      right = true;
      await tester.pumpWidget(fixture());
      await _drain(tester);
      expect(bridge.uploads, hasLength(1));
      bridge.release();
      await _drain(tester);
      expect(bridge.peak, 1);
      expect(bridge.uploads, hasLength(2));
      expect(bridge.uploads.last['id'], bridge.uploads.first['id']);
      expect(
        bridge.uploads.last['version']! as int,
        greaterThan(bridge.uploads.first['version']! as int),
      );
      expect((await _pixels(tester, bridge.uploads.last)).rgba.take(4), [
        0,
        0,
        255,
        255,
      ]);
      expect(bridge.scenes.last['visible'], isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('scale changes retire pending captures before upload', (
    tester,
  ) async {
    await tester.pumpWidget(
      _fixture((context) => _artwork(context, Colors.red)),
    );
    await tester.pumpWidget(
      _fixture(
        (context) => _artwork(context, const Color(0xff0000ff)),
        scale: 2,
      ),
    );
    await _drain(tester);
    expect(bridge.uploads, hasLength(1));
    final upload = bridge.uploads.single;
    final pixels = await _pixels(tester, upload);
    expect(upload['scale'], 2);
    expect((pixels.width, pixels.height), (48, 48));
    expect(pixels.rgba.take(4), [0, 0, 255, 255]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scale changes during upload produce matching trailing artwork', (
    tester,
  ) async {
    bridge.blocked = true;
    await tester.pumpWidget(
      _fixture((context) => _artwork(context, Colors.red)),
    );
    await _drain(tester);
    expect(bridge.uploads, hasLength(1));
    await tester.pumpWidget(
      _fixture(
        (context) => _artwork(context, const Color(0xff0000ff)),
        scale: 2,
      ),
    );
    await _drain(tester);
    expect(bridge.uploads, hasLength(1));
    bridge.release();
    await _drain(tester);
    expect(bridge.peak, 1);
    expect(bridge.uploads, hasLength(2));
    expect(bridge.uploads.first['scale'], 1);
    expect(bridge.uploads.last['scale'], 2);
    final pixels = await _pixels(tester, bridge.uploads.last);
    expect((pixels.width, pixels.height), (48, 48));
    expect(pixels.rgba.take(4), [0, 0, 255, 255]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed bridge keeps fallback and a later repaint recovers', (
    tester,
  ) async {
    bridge.fail = true;
    await tester.pumpWidget(
      _fixture((context) => _artwork(context, Colors.red)),
    );
    await _drain(tester);
    expect(bridge.uploads, hasLength(1));
    expect(bridge.scenes.where((scene) => scene['visible'] == true), isEmpty);
    bridge.fail = false;
    await tester.pumpWidget(
      _fixture((context) => _artwork(context, const Color(0xff0000ff))),
    );
    await _drain(tester);
    expect(bridge.uploads, hasLength(2));
    expect((await _pixels(tester, bridge.uploads.last)).rgba.take(4), [
      0,
      0,
      255,
      255,
    ]);
    expect(bridge.scenes.last['visible'], isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary Native dock label updates deliver completed artwork', (
    tester,
  ) async {
    Widget fixture(String label) => _fixture(
      (_) => SizedBox(
        width: 160,
        child: DMobileDockAction(
          icon: const Icon(Icons.add),
          label: label,
          onPressed: () {},
        ),
      ),
    );

    await tester.pumpWidget(fixture('First'));
    await _drain(tester);
    expect(bridge.uploads, isNotEmpty);
    final first = bridge.uploads.last;
    final firstPixels = await _pixels(tester, first);
    bridge.uploads.clear();
    await tester.pumpWidget(fixture('Latest'));
    await _drain(tester);
    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('First'), findsNothing);
    expect(bridge.uploads, hasLength(1));
    final latest = bridge.uploads.single;
    expect(latest['id'], first['id']);
    expect(latest['version']! as int, greaterThan(first['version']! as int));
    expect((await _pixels(tester, latest)).rgba, isNot(firstPixels.rgba));
    expect(bridge.peak, 1);
    expect(bridge.scenes.last['visible'], isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final blocked in [false, true]) {
    testWidgets(
      'chat send artwork returns after loading with blocked bridge $blocked',
      (tester) async {
        Widget fixture({bool loading = false, bool enabled = false}) =>
            _fixture((context) {
              final colors = DTokens.of(context).buttonTheme.primary;
              return DButton.iconOnly(
                size: DButtonSize.toolbar,
                foregroundColor: colors.foreground,
                backgroundColor: colors.background,
                interactiveBackgroundColor: colors.hover,
                icon: const DIcon(DIcons.paperPlane, size: 12),
                tooltip: 'Send message',
                semanticLabel: 'Send',
                onPressed: enabled ? () {} : null,
                loading: loading,
              );
            });

        await tester.pumpWidget(fixture());
        await _drain(tester);
        expect(bridge.uploads, isNotEmpty);
        final disabled = await _pixels(tester, bridge.uploads.last);
        expect(disabled.rgba.where((value) => value != 0), isNotEmpty);

        await tester.pumpWidget(fixture(enabled: true));
        await tester.pump(const Duration(milliseconds: 300));
        await _drain(tester);
        bridge.blocked = blocked;
        await tester.pumpWidget(fixture(loading: true));
        await tester.pump(const Duration(milliseconds: 300));
        await _drain(tester);
        expect(find.byType(DSpinner), findsOneWidget);
        final loading = await _pixels(tester, bridge.uploads.last);
        expect(loading.rgba, isNot(disabled.rgba));

        await tester.pumpWidget(fixture());
        await tester.pump(const Duration(milliseconds: 300));
        bridge.release();
        await _drain(tester);
        expect(find.byType(DSpinner), findsNothing);
        final finished = await _pixels(tester, bridge.uploads.last);
        expect(
          finished.rgba,
          disabled.rgba,
          reason:
              'The native button must receive the restored paper-plane icon.',
        );
        expect(bridge.peak, 1);
        expect(bridge.scenes.last['visible'], isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('descendant repaint boundaries refresh native artwork', (
    tester,
  ) async {
    Widget fixture(Color color) => _fixture(
      (context) => NativeGlassContent(
        group: NativeGlass.of(context)!,
        child: RepaintBoundary(
          child: SizedBox.square(
            dimension: 24,
            child: ColoredBox(color: color),
          ),
        ),
      ),
    );

    await tester.pumpWidget(fixture(const Color(0xffff0000)));
    await _drain(tester);
    expect(bridge.uploads, isNotEmpty);
    expect((await _pixels(tester, bridge.uploads.last)).rgba.take(4), [
      255,
      0,
      0,
      255,
    ]);

    await tester.pumpWidget(fixture(const Color(0xff0000ff)));
    await _drain(tester);
    expect((await _pixels(tester, bridge.uploads.last)).rgba.take(4), [
      0,
      0,
      255,
      255,
    ]);
    expect(tester.takeException(), isNull);
  });
}
