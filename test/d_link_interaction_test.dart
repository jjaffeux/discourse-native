import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
  home: Scaffold(
    body: Align(alignment: Alignment.topLeft, child: child),
  ),
);

void main() {
  final controls = <(String, Widget Function(VoidCallback))>[
    (
      'Item',
      (activate) => DItem(
        size: DItemSize.artwork,
        fitContent: true,
        link: true,
        onPressed: activate,
        children: const [Text('Open link')],
      ),
    ),
    (
      'Button',
      (activate) => DButton(
        variant: DButtonVariant.inline,
        density: DButtonDensity.inlineMetadata,
        isLink: true,
        onPressed: activate,
        label: const Text('Open link'),
      ),
    ),
    (
      'Badge link',
      (activate) =>
          DBadge.link(onPressed: activate, child: const Text('Open link')),
    ),
    (
      'Badge action',
      (activate) =>
          DBadge.action(onPressed: activate, child: const Text('Open link')),
    ),
    (
      'Inline badge',
      (activate) =>
          DBadge.inline(onPressed: activate, child: const Text('Open link')),
    ),
    (
      'Bubble link',
      (activate) => DBubble(
        variant: DBubbleVariant.neutral,
        children: [
          DBubbleContent(
            action: DBubbleContentAction.link,
            onPressed: activate,
            child: const Text('Open link'),
          ),
        ],
      ),
    ),
  ];

  for (final (name, build) in controls) {
    testWidgets(
      '$name retains primary activation and adds modified navigation',
      (tester) async {
        var primary = 0;
        final activations = <DLinkActivation>[];
        await tester.pumpWidget(
          _host(
            DLinkInteraction(
              onActivate: activations.add,
              child: build(() => primary++),
            ),
          ),
        );
        final link = find.text('Open link');
        await tester.tap(link, kind: PointerDeviceKind.mouse);
        expect(primary, 1);
        expect(activations, isEmpty);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.tap(link, kind: PointerDeviceKind.mouse);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(primary, 1);
        expect(activations, [DLinkActivation.shiftedPrimary]);

        await tester.tap(
          link,
          kind: PointerDeviceKind.mouse,
          buttons: kMiddleMouseButton,
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.tap(
          link,
          kind: PointerDeviceKind.mouse,
          buttons: kMiddleMouseButton,
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(primary, 1);
        expect(activations, [
          DLinkActivation.shiftedPrimary,
          DLinkActivation.middle,
          DLinkActivation.shiftedMiddle,
        ]);
      },
    );
  }

  testWidgets('Shift interception does not consume nested ordinary controls', (
    tester,
  ) async {
    var row = 0;
    var nested = 0;
    final activations = <DLinkActivation>[];
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 300,
          child: DLinkInteraction(
            onActivate: activations.add,
            child: DItem(
              onPressed: () => row++,
              link: true,
              children: [
                const DItemContent(children: [Text('Row')]),
                DItemActions(
                  children: [
                    DButton(
                      onPressed: () => nested++,
                      label: const Text('Nested action'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Nested action'), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(nested, 1);
    expect(row, 0);
    expect(activations, isEmpty);
  });

  testWidgets('disabled Shift interception retains ordinary child activation', (
    tester,
  ) async {
    var primary = 0;
    final activations = <DLinkActivation>[];
    await tester.pumpWidget(
      _host(
        DLinkInteraction(
          shiftPrimaryEnabled: false,
          onActivate: activations.add,
          child: DButton(
            onPressed: () => primary++,
            label: const Text('Open link'),
          ),
        ),
      ),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Open link'), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(primary, 1);
    expect(activations, isEmpty);
  });

  testWidgets('middle drag and cancellation do not activate links', (
    tester,
  ) async {
    final activations = <DLinkActivation>[];
    await tester.pumpWidget(
      _host(
        DLinkInteraction(
          onActivate: activations.add,
          child: DItem(
            size: DItemSize.artwork,
            fitContent: true,
            onPressed: () {},
            children: const [
              SizedBox(width: 120, height: 24, child: Text('Open link')),
            ],
          ),
        ),
      ),
    );
    final center = tester.getCenter(find.text('Open link'));
    final drag = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await drag.moveBy(const Offset(100, 0));
    await drag.up();
    final cancelled = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await cancelled.cancel();
    expect(activations, isEmpty);
  });

  testWidgets(
    'supplemental link gestures keep artwork bounds and outside gaps',
    (tester) async {
      var primary = 0;
      final activations = <DLinkActivation>[];
      const artwork = Key('link-artwork');
      const target = Key('link-target');
      await tester.pumpWidget(
        _host(
          DLinkInteraction(
            key: target,
            onActivate: activations.add,
            child: DItem(
              size: DItemSize.artwork,
              fitContent: true,
              onPressed: () => primary++,
              children: const [
                SizedBox(
                  key: artwork,
                  width: 90,
                  height: 24,
                  child: ColoredBox(color: Colors.blue),
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        tester.getRect(find.byKey(target)),
        tester.getRect(find.byKey(artwork)),
      );
      final outside =
          tester.getRect(find.byKey(artwork)).bottomRight + const Offset(1, 1);
      await tester.tapAt(outside);
      await tester.tapAt(
        outside,
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      expect(primary, 0);
      expect(activations, isEmpty);
    },
  );
}
