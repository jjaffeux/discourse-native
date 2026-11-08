import 'dart:convert';

import 'package:discourse_native/src/shell/resizable_pane.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tab_switch_fixture.dart';

const _ticks = 20;

void main() {
  setUp(() {
    const channel = MethodChannel('org.discourse.native/notification_opens');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  });

  testWidgets(
    'dragging a pane rebuilds only what its width changes',
    (tester) async {
      await pumpTabSwitchFixture(tester);
      await tester.pumpAndSettle();
      await tapDocumentTab(tester, 'reader-a');
      await tester.pumpAndSettle();

      final report = <String, Object>{};
      for (final handle in const ['sidebar', 'main-panel']) {
        report[handle] = await _measureDrag(tester, handle);
      }
      debugPrint('PANEL_RESIZE_WORK ${jsonEncode(report)}');
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );
}

Future<Map<String, Object>> _measureDrag(
  WidgetTester tester,
  String handle,
) async {
  final finder = find.byKey(ValueKey('$handle-resize-handle'));
  expect(finder, findsOneWidget);
  final pane = find.ancestor(of: finder, matching: find.byType(ResizablePane));
  final gesture = await tester.startGesture(
    tester.getCenter(finder),
    kind: PointerDeviceKind.mouse,
  );
  // Move clear of the minimum first, so that every counted tick resizes.
  await gesture.moveBy(const Offset(40, 0));
  await tester.pump();
  await gesture.moveBy(const Offset(2, 0));
  await tester.pump();

  var builds = 0;
  var tickElements = <Element>{};
  var uniqueElements = 0;
  final causes = <String, int>{};
  final previous = debugOnRebuildDirtyWidget;
  addTearDown(() => debugOnRebuildDirtyWidget = previous);
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    previous?.call(element, builtOnce);
    builds++;
    tickElements.add(element);
  };
  var last = tester.getSize(pane).width;
  for (var tick = 0; tick < _ticks; tick++) {
    await gesture.moveBy(Offset(tick.isEven ? 2 : -2, 0));
    await tester.pump();
    final width = tester.getSize(pane).width;
    expect(width, isNot(last), reason: 'Tick $tick must resize the pane.');
    last = width;
    uniqueElements += tickElements.length;
    for (final element in tickElements) {
      if (!element.mounted) continue;
      causes.update(
        _causeOf(element, tickElements),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    tickElements = {};
  }
  debugOnRebuildDirtyWidget = previous;
  await gesture.up();
  await tester.pumpAndSettle();

  final ranked = causes.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return {
    'buildsPerTick': builds / _ticks,
    'elementsPerTick': uniqueElements / _ticks,
    'causes': {
      for (final entry in ranked.take(24)) entry.key: entry.value / _ticks,
    },
  };
}

/// The boundary that made [element] rebuild: the nearest layout-time builder
/// above it, or the outermost widget of the contiguous rebuild it belongs to.
String _causeOf(Element element, Set<Element> rebuilt) {
  var cursor = element;
  while (true) {
    Element? parent;
    cursor.visitAncestorElements((ancestor) {
      parent = ancestor;
      return false;
    });
    if (parent == null) return 'root';
    if (parent is RenderObjectElement) {
      if ((parent! as RenderObjectElement).renderObject
          is RenderAbstractLayoutBuilderMixin) {
        return parent!.debugGetCreatorChain(4);
      }
    } else if (!rebuilt.contains(parent)) {
      return cursor.debugGetCreatorChain(4);
    }
    cursor = parent!;
  }
}
