import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/ui/foundation/native_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

typedef _Scene = Map<Object?, Object?>;

List<_Scene> _list(Object? value) => (value! as List<Object?>).cast<_Scene>();

Rect _rect(Object? value) {
  final coordinates = (value! as List<Object?>).cast<double>();
  return Rect.fromLTWH(
    coordinates[0],
    coordinates[1],
    coordinates[2],
    coordinates[3],
  );
}

Widget _fixture(Widget child, {TargetPlatform platform = TargetPlatform.iOS}) =>
    MaterialApp(
      theme: DMaterialTheme.apply(
        AppTheme.light.copyWith(platform: platform),
        DAppearanceMaterial.liquidGlass,
      ),
      home: Align(alignment: Alignment.topLeft, child: child),
    );

Widget _button(String name) =>
    DButton(key: ValueKey(name), label: Text(name), onPressed: () {});

Future<void> _drain(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }
}

void main() {
  final scenes = <_Scene>[];
  final pendingImages = <Completer<void>>[];
  var blockImages = false;

  setUp(() {
    scenes.clear();
    pendingImages.clear();
    blockImages = false;
    NativeGlass.available.value = true;
    NativeGlass.disabled.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeGlass.channel, (call) async {
          if (call.method == 'available') return true;
          if (call.method == 'scene') scenes.add(call.arguments as _Scene);
          if (call.method == 'image' && blockImages) {
            final completion = Completer<void>();
            pendingImages.add(completion);
            await completion.future;
          }
          return null;
        });
  });

  tearDown(() {
    for (final completion in pendingImages) {
      if (!completion.isCompleted) completion.complete();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeGlass.channel, null);
    NativeGlass.available.value = false;
    NativeGlass.disabled.value = false;
  });

  List<_Scene> elements() =>
      _list(_list(scenes.last['groups']).single['elements']);

  testWidgets('a macOS control draws system glass without a scope', (
    tester,
  ) async {
    await tester.pumpWidget(
      _fixture(_button('Desktop'), platform: TargetPlatform.macOS),
    );
    await _drain(tester);

    final element = elements().singleWhere(
      (element) => element['glass'] == true,
    );
    expect(
      _rect(element['rect']),
      tester.getRect(find.byKey(const ValueKey('Desktop'))),
    );
    expect(find.byType(LiquidGlass), findsNothing);
  });

  testWidgets('an iOS control without a scope keeps Flutter glass', (
    tester,
  ) async {
    await tester.pumpWidget(_fixture(_button('Phone')));
    await _drain(tester);

    expect(scenes.where((scene) => scene['visible'] == true), isEmpty);
    expect(find.byType(LiquidGlass), findsWidgets);
  });

  testWidgets('a macOS control in a list is clipped to its viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      _fixture(
        SizedBox(
          width: 200,
          height: 60,
          child: ListView(
            children: [
              const SizedBox(height: 40),
              Align(alignment: Alignment.topLeft, child: _button('Row')),
            ],
          ),
        ),
        platform: TargetPlatform.macOS,
      ),
    );
    await _drain(tester);

    final group = _list(scenes.last['groups']).single;
    expect(_rect(group['clip']), tester.getRect(find.byType(ListView)));
  });

  testWidgets('unchanged natural frames send no additional scene', (
    tester,
  ) async {
    await tester.pumpWidget(
      _fixture(NativeGlassScope(child: _button('Still'))),
    );
    await _drain(tester);
    expect(scenes.last['visible'], isTrue);
    expect(elements(), isNotEmpty);
    final sent = scenes.length;

    for (var frame = 0; frame < 12; frame++) {
      tester.binding.scheduleFrame();
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(scenes, hasLength(sent));
    expect(tester.takeException(), isNull);
  });

  testWidgets('retained controls follow ancestor geometry and visibility', (
    tester,
  ) async {
    final ancestor = ValueNotifier((
      offset: Offset.zero,
      scale: 1.0,
      opacity: 1.0,
      offstage: false,
      height: 80.0,
    ));
    addTearDown(ancestor.dispose);
    var builds = 0;
    await tester.pumpWidget(
      _fixture(
        ValueListenableBuilder(
          valueListenable: ancestor,
          builder: (context, value, child) => Transform.translate(
            offset: value.offset,
            child: Transform.scale(
              scale: value.scale,
              alignment: Alignment.topLeft,
              child: Opacity(
                opacity: value.opacity,
                child: Offstage(
                  offstage: value.offstage,
                  child: ClipRect(
                    child: SizedBox(
                      width: 240,
                      height: value.height,
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minHeight: 80,
                        maxHeight: 80,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: NativeGlassScope(
            child: Align(
              alignment: Alignment.topLeft,
              child: Builder(
                builder: (context) {
                  builds++;
                  return _button('Retained');
                },
              ),
            ),
          ),
        ),
      ),
    );
    await _drain(tester);
    final original = elements()
        .map((element) => _rect(element['rect']))
        .toList();
    final ids = elements().map((element) => element['id']).toList();
    final contentIds = elements()
        .where((element) => element['image'] != -1)
        .map((element) => element['id'])
        .toList();
    final initialBuilds = builds;

    ancestor.value = (
      offset: const Offset(23, 41),
      scale: 1.0,
      opacity: 0.4,
      offstage: false,
      height: 20.0,
    );
    await tester.pump();
    expect(elements().map((element) => element['id']), ids);
    for (var index = 0; index < original.length; index++) {
      expect(
        _rect(elements()[index]['rect']),
        original[index].shift(const Offset(23, 41)),
      );
      expect(elements()[index]['opacity'], 0.4);
    }
    expect(
      _rect(_list(scenes.last['groups']).single['clip']),
      const Rect.fromLTWH(23, 41, 240, 20),
    );

    ancestor.value = (
      offset: const Offset(23, 41),
      scale: 1.0,
      opacity: 0.4,
      offstage: true,
      height: 20.0,
    );
    await tester.pump();
    expect(scenes.last['visible'], isFalse);
    expect(scenes.last['groups'], isEmpty);
    expect(scenes.last['alive']! as List<Object?>, containsAll(contentIds));

    ancestor.value = (
      offset: const Offset(23, 41),
      scale: 1.0,
      opacity: 0.0,
      offstage: false,
      height: 20.0,
    );
    await tester.pump();
    expect(scenes.last['visible'], isFalse);

    ancestor.value = (
      offset: const Offset(7, 11),
      scale: 2.0,
      opacity: 1.0,
      offstage: false,
      height: 80.0,
    );
    await tester.pump();
    expect(scenes.last['visible'], isTrue);
    expect(elements().map((element) => element['id']), ids);
    for (var index = 0; index < original.length; index++) {
      final rect = original[index];
      expect(
        _rect(elements()[index]['rect']),
        Rect.fromLTWH(
          rect.left * 2 + 7,
          rect.top * 2 + 11,
          rect.width * 2,
          rect.height * 2,
        ),
      );
    }
    expect(builds, initialBuilds);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scrolling refreshes a retained control scene and viewport clip',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var builds = 0;
      await tester.pumpWidget(
        _fixture(
          SizedBox(
            width: 240,
            height: 160,
            child: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: [
                  const SizedBox(height: 80),
                  NativeGlassScope(
                    child: Builder(
                      builder: (context) {
                        builds++;
                        return _button('Scroll');
                      },
                    ),
                  ),
                  const SizedBox(height: 400),
                ],
              ),
            ),
          ),
        ),
      );
      await _drain(tester);
      final before = elements()
          .map((element) => _rect(element['rect']))
          .toList();
      final initialBuilds = builds;
      controller.jumpTo(37);
      await tester.pump();

      for (var index = 0; index < before.length; index++) {
        expect(
          _rect(elements()[index]['rect']),
          before[index].shift(const Offset(0, -37)),
        );
      }
      expect(
        _rect(_list(scenes.last['groups']).single['clip']),
        const Rect.fromLTWH(0, 0, 240, 160),
      );
      expect(builds, initialBuilds);
    },
  );

  testWidgets('keyed control reordering updates element paint order', (
    tester,
  ) async {
    final reverse = ValueNotifier(false);
    addTearDown(reverse.dispose);
    final first = _button('First');
    final second = _button('Second');
    await tester.pumpWidget(
      _fixture(
        NativeGlassScope(
          child: ValueListenableBuilder(
            valueListenable: reverse,
            builder: (context, value, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: value ? [second, first] : [first, second],
            ),
          ),
        ),
      ),
    );
    await _drain(tester);
    final firstRect = tester.getRect(find.byKey(const ValueKey('First')));
    final secondRect = tester.getRect(find.byKey(const ValueKey('Second')));
    final firstIds = elements()
        .where((element) => firstRect.contains(_rect(element['rect']).center))
        .map((element) => element['id'])
        .toList();
    final secondIds = elements()
        .where((element) => secondRect.contains(_rect(element['rect']).center))
        .map((element) => element['id'])
        .toList();
    expect(firstIds, isNotEmpty);
    expect(secondIds, isNotEmpty);
    expect(elements().map((element) => element['id']), [
      ...firstIds,
      ...secondIds,
    ]);

    reverse.value = true;
    await tester.pump();
    expect(elements().map((element) => element['id']), [
      ...secondIds,
      ...firstIds,
    ]);
  });

  testWidgets('keyed group reordering and removal update the scene', (
    tester,
  ) async {
    final order = ValueNotifier(['First', 'Second']);
    addTearDown(order.dispose);
    final groups = {
      for (final name in order.value)
        name: NativeGlassScope(
          key: ValueKey(name),
          child: _button('$name control'),
        ),
    };
    await tester.pumpWidget(
      _fixture(
        ValueListenableBuilder(
          valueListenable: order,
          builder: (context, value, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final name in value) groups[name]!],
          ),
        ),
      ),
    );
    await _drain(tester);
    final original = _list(scenes.last['groups']);
    final firstId = original[0]['id'];
    final secondId = original[1]['id'];
    final secondContent = _list(original[1]['elements'])
        .where((element) => element['image'] != -1)
        .map((element) => element['id'])
        .toList();

    order.value = ['Second', 'First'];
    await tester.pump();
    expect(_list(scenes.last['groups']).map((group) => group['id']), [
      secondId,
      firstId,
    ]);

    order.value = ['First'];
    await tester.pump();
    expect(_list(scenes.last['groups']).single['id'], firstId);
    for (final id in secondContent) {
      expect(scenes.last['alive']! as List<Object?>, isNot(contains(id)));
    }

    order.value = [];
    await tester.pump();
    expect(scenes.last['visible'], isFalse);
    expect(scenes.last['groups'], isEmpty);
    expect(scenes.last['alive'], isEmpty);
  });

  testWidgets('remounted content keeps its positional fallback alive', (
    tester,
  ) async {
    final name = ValueNotifier('Old');
    addTearDown(name.dispose);
    await tester.pumpWidget(
      _fixture(
        NativeGlassScope(
          child: ValueListenableBuilder(
            valueListenable: name,
            builder: (context, value, _) => _button(value),
          ),
        ),
      ),
    );
    await _drain(tester);
    final previous = elements().singleWhere(
      (element) => element['image'] != -1,
    )['id'];
    blockImages = true;
    name.value = 'New';
    await tester.pump();
    await _drain(tester);

    final replacement = elements().singleWhere(
      (element) => element['image'] != -1,
    );
    expect(replacement['id'], isNot(previous));
    expect(replacement['image'], 0);
    expect(replacement['fallback'], previous);
    expect(
      scenes.last['alive']! as List<Object?>,
      containsAll([previous, replacement['id']]),
    );

    blockImages = false;
    for (final completion in pendingImages) {
      if (!completion.isCompleted) completion.complete();
    }
    await _drain(tester);
    final ready = elements().singleWhere((element) => element['image'] != -1);
    expect(ready['image'], greaterThan(0));
    expect(ready['fallback'], isNull);
    expect(scenes.last['alive']! as List<Object?>, isNot(contains(previous)));
    expect(tester.takeException(), isNull);
  });
}
