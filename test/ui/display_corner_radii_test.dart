import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('org.discourse.native/window_geometry');
const _materialChannel = MethodChannel(
  'org.discourse.native/material_accessibility',
);

Map<String, double> _geometry({
  double radius = 47,
  Size size = const Size(800, 600),
}) => {
  'width': size.width,
  'height': size.height,
  'topLeft': radius,
  'topRight': radius + 1,
  'bottomLeft': radius + 2,
  'bottomRight': radius + 3,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MediaQueryData observed;

  void testNative(String name, WidgetTesterCallback callback) => testWidgets(
    name,
    callback,
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  Widget host({BorderRadius? frameworkRadii}) {
    return MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).applyDisplayCornerRadii(frameworkRadii),
        child: DDisplayCornerRadii(child: child!),
      ),
      home: Builder(
        builder: (context) {
          observed = MediaQuery.of(context);
          return const SizedBox();
        },
      ),
    );
  }

  Widget appRegionsHost() => MaterialApp(
    builder: (context, child) => DDisplayCornerRadii(
      child: DMaterialAccessibility(
        child: DFocusHighlight(child: DToaster(child: child!)),
      ),
    ),
    home: Builder(
      builder: (context) => Column(
        children: [
          Text(DMaterialTheme.reducedOf(context) ? 'Reduced' : 'Transparent'),
          DButton(
            onPressed: () => DToast.of(context).add(
              const DToastOptions(description: 'Active toast', duration: null),
            ),
            label: const Text('Show toast'),
          ),
        ],
      ),
    ),
  );

  Future<void> push(Object? payload) async {
    await messenger.handlePlatformMessage(
      _channel.name,
      _channel.codec.encodeMethodCall(MethodCall('geometryChanged', payload)),
      (_) {},
    );
  }

  Future<void> reduceTransparency(bool reduced) async {
    await messenger.handlePlatformMessage(
      _materialChannel.name,
      _materialChannel.codec.encodeMethodCall(
        MethodCall('reduceTransparencyChanged', reduced),
      ),
      (_) {},
    );
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    messenger.setMockMethodCallHandler(_materialChannel, null);
  });

  testNative('native accessibility updates survive geometry changes', (
    tester,
  ) async {
    final initial = Completer<Object?>();
    messenger.setMockMethodCallHandler(_channel, (_) => initial.future);
    messenger.setMockMethodCallHandler(_materialChannel, (_) async => false);
    await tester.pumpWidget(appRegionsHost());
    await tester.pump();
    await reduceTransparency(true);
    await tester.pump();
    expect(find.text('Reduced'), findsOneWidget);
    await reduceTransparency(false);
    await tester.pump();
    expect(find.text('Transparent'), findsOneWidget);

    initial.complete(_geometry());
    await tester.pump();
    await reduceTransparency(true);
    await tester.pump();
    expect(find.text('Reduced'), findsOneWidget);

    await push(null);
    await tester.pump();
    await reduceTransparency(false);
    await tester.pump();
    expect(find.text('Transparent'), findsOneWidget);

    await push(_geometry());
    await tester.pump();
    await reduceTransparency(true);
    await tester.pump();
    expect(find.text('Reduced'), findsOneWidget);
  });

  testNative('an active toast survives geometry changes', (tester) async {
    final initial = Completer<Object?>();
    messenger.setMockMethodCallHandler(_channel, (_) => initial.future);
    messenger.setMockMethodCallHandler(_materialChannel, (_) async => false);
    await tester.pumpWidget(appRegionsHost());
    await tester.pump();
    await tester.tap(find.text('Show toast'));
    await tester.pump();
    expect(find.text('Active toast'), findsOneWidget);

    initial.complete(_geometry());
    await tester.pump();
    expect(find.text('Active toast'), findsOneWidget);
    await push(null);
    await tester.pump();
    expect(find.text('Active toast'), findsOneWidget);
    await push(_geometry());
    await tester.pump();
    expect(find.text('Active toast'), findsOneWidget);
  });

  testNative('native points reach descendants without pixel scaling', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(_channel, (_) async => _geometry());
    await tester.pumpWidget(host());
    await tester.pump();
    expect(
      observed.displayCornerRadii,
      const BorderRadius.only(
        topLeft: Radius.circular(47),
        topRight: Radius.circular(48),
        bottomLeft: Radius.circular(49),
        bottomRight: Radius.circular(50),
      ),
    );
  });

  testNative('a newer native push wins over the initial reply', (tester) async {
    final initial = Completer<Object?>();
    messenger.setMockMethodCallHandler(_channel, (_) => initial.future);
    await tester.pumpWidget(host());
    await push(_geometry(radius: 62));
    await tester.pump();
    initial.complete(_geometry());
    await tester.pump();
    expect(observed.displayCornerRadii?.topLeft.x, 62);
  });

  testNative('zero is a resolved rectangular viewport', (tester) async {
    messenger.setMockMethodCallHandler(
      _channel,
      (_) async => {
        ..._geometry(),
        'topLeft': 0,
        'topRight': 0,
        'bottomLeft': 0,
        'bottomRight': 0,
      },
    );
    await tester.pumpWidget(host());
    await tester.pump();
    expect(observed.displayCornerRadii, BorderRadius.zero);
  });

  for (final payload in <Object?>[
    null,
    'invalid',
    <String, Object?>{},
    {..._geometry(), 'bottomLeft': -1},
    {..._geometry(), 'topLeft': double.nan},
    {..._geometry(), 'height': double.infinity},
    {..._geometry(), 'width': 0},
    {..._geometry(), 'bottomRight': '62'},
  ]) {
    testNative('unavailable or invalid geometry $payload preserves fallback', (
      tester,
    ) async {
      messenger.setMockMethodCallHandler(_channel, (_) async => payload);
      await tester.pumpWidget(host());
      await tester.pump();
      expect(observed.displayCornerRadii, isNull);
    });
  }

  testNative(
    'native pushes clear unavailable geometry and recover on attachment',
    (tester) async {
      messenger.setMockMethodCallHandler(_channel, (_) async => null);
      await tester.pumpWidget(host());
      await tester.pump();
      expect(observed.displayCornerRadii, isNull);
      await push(_geometry());
      await tester.pump();
      expect(observed.displayCornerRadii, isNotNull);
      await push(null);
      await tester.pump();
      expect(observed.displayCornerRadii, isNull);
    },
  );

  testNative('framework metrics take priority over native values', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(_channel, (_) async => _geometry());
    const framework = BorderRadius.all(Radius.circular(18));
    await tester.pumpWidget(host(frameworkRadii: framework));
    await tester.pump();
    expect(observed.displayCornerRadii, framework);
  });

  testNative(
    'viewport changes reject old geometry until native layout arrives',
    (tester) async {
      messenger.setMockMethodCallHandler(_channel, (_) async => _geometry());
      await tester.pumpWidget(host());
      await tester.pump();
      expect(observed.displayCornerRadii?.topLeft.x, 47);
      tester.view.physicalSize =
          const Size(600, 800) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pump();
      expect(observed.displayCornerRadii, isNull);
      await push(_geometry(size: const Size(600, 800), radius: 62));
      await tester.pump();
      expect(observed.displayCornerRadii?.topLeft.x, 62);
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    testWidgets(
      '$platform preserves existing metrics without a native request',
      (tester) async {
        var requests = 0;
        messenger.setMockMethodCallHandler(_channel, (_) async {
          requests++;
          return _geometry();
        });
        const framework = BorderRadius.all(Radius.circular(18));
        await tester.pumpWidget(host(frameworkRadii: framework));
        await tester.pump();
        expect(requests, 0);
        expect(observed.displayCornerRadii, framework);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  for (final error in [
    MissingPluginException(),
    PlatformException(code: 'unavailable'),
  ]) {
    testNative('$error preserves the fallback', (tester) async {
      messenger.setMockMethodCallHandler(_channel, (_) async => throw error);
      await tester.pumpWidget(host());
      await tester.pump();
      expect(observed.displayCornerRadii, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testNative('a pending response after disposal has no effect', (tester) async {
    final initial = Completer<Object?>();
    messenger.setMockMethodCallHandler(_channel, (_) => initial.future);
    await tester.pumpWidget(host());
    await tester.pumpWidget(const SizedBox());
    initial.complete(_geometry());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
