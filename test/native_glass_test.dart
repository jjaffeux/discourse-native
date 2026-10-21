import 'dart:io';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/ui/foundation/native_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'd_mobile_dock_test.dart' show fixture, sendButtonFixture;

final _glass = DMaterialTheme.apply(
  AppTheme.light.copyWith(platform: TargetPlatform.iOS),
  DAppearanceMaterial.liquidGlass,
);

typedef _Scene = Map<Object?, Object?>;

final _opensOverlay = RegExp(r'\bOverlay(Portal(\.\w+)?|Entry)\(');

List<_Scene> _list(Object? value) =>
    (value! as List<Object?>).cast<_Scene>().toList();

Rect _rect(Object? value) {
  final values = (value! as List<Object?>).cast<double>();
  return Rect.fromLTWH(values[0], values[1], values[2], values[3]);
}

void main() {
  final scenes = <_Scene>[];
  final images = <int, int>{};

  setUp(() {
    scenes.clear();
    images.clear();
    NativeGlass.available.value = true;
    NativeGlass.disabled.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeGlass.channel, (call) async {
          switch (call.method) {
            case 'available':
              return NativeGlass.available.value;
            case 'scene':
              scenes.add(call.arguments as _Scene);
            case 'image':
              final payload = call.arguments as _Scene;
              images[payload['id']! as int] =
                  (payload['png']! as Uint8List).length;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeGlass.channel, null);
    NativeGlass.available.value = false;
    NativeGlass.disabled.value = false;
  });

  Future<_Scene> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pump();
    return scenes.last;
  }

  testWidgets('system glass draws the dock and Flutter draws none', (
    tester,
  ) async {
    await tester.pumpWidget(fixture(theme: _glass));
    final scene = await settle(tester);

    expect(find.byType(LiquidGlass), findsNothing);
    expect(scene['visible'], isTrue);
    final group = _list(scene['groups']).single;
    expect(group['merge'], isFalse);
    final elements = _list(group['elements']);
    final capsule = elements.singleWhere((element) => element['image'] == -1);
    expect(capsule['glass'], isTrue);
    expect(capsule['radius'], isNull);
    expect(
      _rect(capsule['rect']),
      tester.getRect(find.byKey(const ValueKey('mobile-dock-surface'))),
    );
    // The capsule is painted first, under its controls.
    expect(elements.first, same(capsule));
    _Scene at(Finder finder) {
      final center = tester.getCenter(finder);
      return elements.singleWhere(
        (element) =>
            element['image'] != -1 && _rect(element['rect']).contains(center),
      );
    }

    expect(at(find.byKey(const ValueKey('Topics')))['glass'], isTrue);
    expect(at(find.byKey(const ValueKey('Start')))['glass'], isFalse);
    expect(at(find.byTooltip('New topic'))['glass'], isTrue);
    for (final element in elements) {
      expect(element['opacity'], 1.0);
      if (element['image'] != -1) {
        expect(images[element['id']], greaterThan(0));
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dock action takes the send button system tint', (
    tester,
  ) async {
    await tester.pumpWidget(sendButtonFixture(_glass));
    final send = _list(
      _list((await settle(tester))['groups']).single['elements'],
    ).singleWhere((element) => element['image'] == -1);
    expect(send['tint'], isNotNull);

    await tester.pumpWidget(fixture(theme: _glass));
    final scene = await settle(tester);
    final elements = _list(_list(scene['groups']).single['elements']);
    _Scene at(Finder finder) {
      final center = tester.getCenter(finder);
      return elements.singleWhere(
        (element) =>
            element['image'] != -1 && _rect(element['rect']).contains(center),
      );
    }

    final action = at(find.byTooltip('New topic'));
    expect(action['glass'], isTrue);
    expect(action['tint'], send['tint']);
    // Only the action is tinted: the capsule and the selected destination
    // keep the stock material.
    for (final element in elements.where((e) => !identical(e, action))) {
      expect(element['tint'], isNull);
    }
    expect(at(find.byKey(const ValueKey('Topics')))['glass'], isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a remounted control never hides the glass or empties it', (
    tester,
  ) async {
    final icon = ValueNotifier(Icons.add);
    addTearDown(icon.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: _glass,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 390,
              child: ValueListenableBuilder<IconData>(
                valueListenable: icon,
                builder: (context, value, _) => DMobileDock(
                  onOverflowChanged: (_) {},
                  destinations: [
                    DMobileDockItem(
                      icon: const Icon(Icons.forum),
                      label: 'Topics',
                      selected: true,
                      onPressed: () {},
                    ),
                  ],
                  more: DMobileDockItem(
                    bare: true,
                    icon: const Icon(Icons.more_vert),
                    label: 'More',
                    onPressed: () {},
                  ),
                  collapsedDestination: DMobileDockItem(
                    collapsed: true,
                    icon: const Icon(Icons.forum),
                    label: 'Reveal',
                    onPressed: () {},
                  ),
                  // A new action icon remounts the action, as the shell does
                  // when the destination changes.
                  action: KeyedSubtree(
                    key: ValueKey(value),
                    child: DMobileDockAction(
                      icon: Icon(value),
                      label: 'Act',
                      onPressed: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect((await settle(tester))['visible'], isTrue);
    final shown = scenes.length;

    icon.value = Icons.edit;
    // Frames only: the new action's image cannot arrive yet.
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final waiting = scenes.skip(shown).toList();
    expect(waiting, isNotEmpty);
    for (final scene in waiting) {
      expect(scene['visible'], isTrue);
      for (final element in _list(_list(scene['groups']).single['elements'])) {
        if (element['image'] == 0) expect(element['fallback'], isNotNull);
      }
    }
    final remounted = _list(
      _list(scenes.last['groups']).single['elements'],
    ).where((element) => element['fallback'] != null);
    expect(remounted, hasLength(1));

    final settled = await settle(tester);
    for (final element in _list(_list(settled['groups']).single['elements'])) {
      expect(element['image'], isNot(0));
      expect(element['fallback'], isNull);
    }
  });

  testWidgets('taps still reach the Flutter controls under system glass', (
    tester,
  ) async {
    var revealed = 0;
    await tester.pumpWidget(
      fixture(theme: _glass, collapsed: true, onReveal: () => revealed++),
    );
    expect((await settle(tester))['visible'], isTrue);

    await tester.tap(find.byKey(const ValueKey('reveal')));
    expect(revealed, 1);
    expect(find.bySemanticsLabel('Reveal navigation'), findsOneWidget);
  });

  testWidgets('a covering route hands the glass back to Flutter', (
    tester,
  ) async {
    await tester.pumpWidget(fixture(theme: _glass));
    expect((await settle(tester))['visible'], isTrue);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (context, _, _) => const SizedBox.shrink(),
      ),
    );
    await tester.pumpAndSettle();
    expect(scenes.last['visible'], isFalse);
    expect(find.byType(LiquidGlass), findsWidgets);

    navigator.pop();
    expect((await settle(tester))['visible'], isTrue);
    expect(find.byType(LiquidGlass), findsNothing);
  });

  testWidgets('an open overlay hands the glass back to Flutter', (
    tester,
  ) async {
    final open = ValueNotifier(false);
    addTearDown(open.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: _glass,
        home: Scaffold(
          body: Stack(
            children: [
              fixture(theme: _glass),
              ValueListenableBuilder<bool>(
                valueListenable: open,
                builder: (context, value, _) => value
                    ? const NativeGlassOccluder(child: SizedBox.shrink())
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
    expect((await settle(tester))['visible'], isTrue);

    open.value = true;
    await tester.pumpAndSettle();
    expect(scenes.last['visible'], isFalse);
    expect(find.byType(LiquidGlass), findsWidgets);

    open.value = false;
    await tester.pumpAndSettle();
    expect((await settle(tester))['visible'], isTrue);
  });

  testWidgets('raised glass reports its shape and content, clipped', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _glass,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ClipRect(
                child: SizedBox(
                  width: 260,
                  height: 24,
                  child: NativeGlassScope(
                    merge: true,
                    child: Row(
                      children: [
                        DButtonGroup(
                          children: [
                            DButton(
                              key: const ValueKey('first'),
                              label: const Text('First'),
                              onPressed: () {},
                            ),
                            DButton(
                              key: const ValueKey('second'),
                              label: const Text('Second'),
                              onPressed: () {},
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final scene = await settle(tester);

    expect(find.byType(LiquidGlass), findsNothing);
    final group = _list(scene['groups']).single;
    expect(group['merge'], isTrue);
    expect(_rect(group['clip']), const Rect.fromLTWH(20, 20, 260, 24));
    final elements = _list(group['elements']);
    final shapes = elements.where((element) => element['image'] == -1);
    final contents = elements.where((element) => element['image'] != -1);
    expect(shapes, hasLength(2));
    expect(contents, hasLength(2));
    final first = tester.getRect(find.byKey(const ValueKey('first')));
    final firstShape = shapes.singleWhere(
      (shape) => _rect(shape['rect']).overlaps(first),
    );
    // Joined segments keep their outer corners and square their seam.
    final radius = (firstShape['radius']! as List<Object?>).cast<double>();
    expect(radius[0], greaterThan(0));
    expect(radius[1], 0);
    // Each surface's content paints above its glass.
    expect(
      elements.indexOf(firstShape),
      lessThan(
        elements.indexWhere(
          (element) =>
              element['image'] != -1 && _rect(element['rect']).overlaps(first),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test('every overlay hands native glass back to Flutter', () {
    // UIKit draws native glass above everything Flutter shows, so anything
    // that opens over the app must count as an occluder while it is mounted.
    const paintsNothingVisible = {
      // A 1x1 offscreen web view that renders diagrams.
      'lib/src/ui/components/d_mermaid.dart',
      // A cursor-only region while a drag is in progress.
      'lib/src/ui/components/d_drag.dart',
    };
    final missing = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          if (file.readAsStringSync() case final source
              when _opensOverlay.hasMatch(source) &&
                  !source.contains('NativeGlassOccluder') &&
                  !paintsNothingVisible.contains(file.path))
            file.path,
    ];
    expect(missing, isEmpty);
  });

  testWidgets('without system glass every surface keeps Flutter glass', (
    tester,
  ) async {
    NativeGlass.available.value = false;
    await tester.pumpWidget(fixture(theme: _glass));
    await tester.pumpAndSettle();

    expect(find.byType(LiquidGlass), findsWidgets);
    expect(scenes, isEmpty);
  });

  testWidgets('the measurement switch restores Flutter glass', (tester) async {
    await tester.pumpWidget(fixture(theme: _glass));
    expect((await settle(tester))['visible'], isTrue);

    NativeGlass.disabled.value = true;
    await tester.pumpAndSettle();
    expect(scenes.last['visible'], isFalse);
    expect(find.byType(LiquidGlass), findsWidgets);
  });
}
