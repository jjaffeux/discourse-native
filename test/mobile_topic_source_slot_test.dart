import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;

List<RenderObject> _ancestors(RenderObject source) {
  final result = <RenderObject>[];
  RenderObject? current = source;
  while (current != null) {
    result.add(current);
    current = current.parent;
  }
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.discourse.native/notification_opens');
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });
  testWidgets(
    'Android source keeps its render ancestors across a reader visit',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      final filter = find.byKey(
        const ValueKey('topic-list-filter-bar'),
        skipOffstage: false,
      );
      final source = tester.renderObject(filter);
      final ancestors = _ancestors(source);
      final originalBounds = tester.getRect(filter);
      await tester.tap(find.byKey(const ValueKey('topic-card-7')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pumpAndSettle();
      expect(tester.renderObject(filter), same(source));
      expect(_ancestors(source), orderedEquals(ancestors));
      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
      );
      await drag.moveBy(const Offset(0, 20));
      await drag.moveBy(const Offset(0, 120));
      await tester.pump();
      await drag.cancel();
      await tester.pumpAndSettle();
      final exit = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
      );
      await exit.moveBy(const Offset(0, 20));
      await exit.moveBy(const Offset(0, 220));
      await tester.pump();
      await exit.up();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpAndSettle();
      expect(shell.currentContent?.id, 'latest');
      expect(tester.getRect(filter), originalBounds);
      expect(tester.renderObject(filter), same(source));
      expect(_ancestors(source), orderedEquals(ancestors));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('retained source updates metrics and labels while covered', (
    tester,
  ) async {
    late StateSetter update;
    var entry = 0;
    var compact = true;
    var label = 'Short';
    var scale = 1.0;
    DPageHeader? active;
    const sourceAction = ValueKey('source-action');
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: DPageHeaderHost(
                identity: entry,
                builder: (_, header, child) =>
                    ValueListenableBuilder<DPageHeader?>(
                      valueListenable: header,
                      child: child,
                      builder: (_, value, child) {
                        active = value;
                        return child!;
                      },
                    ),
                child: DSheetViewport(
                  onDismiss: entry == 0 ? null : () => update(() => entry = 0),
                  underlay: DPageSurface.headed(
                    title: const Text('Source'),
                    controls: DFitRow(
                      compact: compact,
                      children: [
                        DFitRowItem(
                          child: Builder(
                            builder: (context) => DButton(
                              key: sourceAction,
                              label: DFitRow.tightOf(context)
                                  ? const Icon(Icons.search)
                                  : Text(label),
                              onPressed: () {},
                            ),
                          ),
                        ),
                      ],
                    ),
                    child: const Text('Live source'),
                  ),
                  content: entry == 0
                      ? null
                      : DSheetContent(
                          key: ValueKey(entry),
                          side: DSheetSide.bottom,
                          variant: DSheetVariant.page,
                          showCloseButton: false,
                          children: [
                            Expanded(
                              child: DPageSurface.headed(
                                title: Text('Reader $entry'),
                                child: const Text('Reader body'),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(active?.titleText, 'Source');
    final action = find.byKey(sourceAction, skipOffstage: false);
    final element = tester.element(action);
    expect(TickerMode.valuesOf(element).enabled, isTrue);
    update(() => entry = 1);
    await tester.pumpAndSettle();
    expect(active?.titleText, 'Reader 1');
    expect(TickerMode.valuesOf(element).enabled, isFalse);
    update(() {
      label = 'Changed label while compact and covered';
      scale = 1.5;
      compact = false;
    });
    await tester.pumpAndSettle();
    expect(find.text(label, skipOffstage: false), findsOneWidget);
    expect(MediaQuery.textScalerOf(element).scale(10), 15);
    expect(TickerMode.valuesOf(element).enabled, isFalse);
    expect(action.hitTestable(), findsNothing);
    final drag = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
    );
    await drag.moveBy(const Offset(0, 20));
    await drag.moveBy(const Offset(0, 260));
    await tester.pump();
    expect(TickerMode.valuesOf(element).enabled, isTrue);
    await drag.up();
    await tester.pump();
    update(() => entry = 2);
    await tester.pumpAndSettle();
    expect(entry, 2);
    expect(active?.titleText, 'Reader 2');
    expect(TickerMode.valuesOf(element).enabled, isFalse);
    update(() => entry = 0);
    await tester.pumpAndSettle();
    expect(tester.element(action), same(element));
    expect(TickerMode.valuesOf(element).enabled, isTrue);
    expect(active?.titleText, 'Source');
    expect(action.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final committed in [true, false]) {
    testWidgets(
      'a cold Android reader replacement resets '
      '${committed ? 'dismissal' : 'cancelled pull'} before any source return',
      (tester) async {
        tester.view.physicalSize = const Size(400, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        late StateSetter update;
        var entry = 1;
        final dismissed = <int>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                final current = entry;
                return DSheetViewport(
                  key: const ValueKey('stable-cold-reader-host'),
                  onDismiss: () {
                    dismissed.add(current);
                    update(() => entry = 0);
                  },
                  underlay: const Text('Source'),
                  content: entry == 0
                      ? null
                      : DSheetContent(
                          key: ValueKey(entry),
                          side: DSheetSide.bottom,
                          variant: DSheetVariant.page,
                          showCloseButton: false,
                          children: [Expanded(child: Text('Reader $entry'))],
                        ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final sheet = find.byType(DSheetContent);
        final resting = tester.getRect(sheet);
        final handle = find.byKey(const ValueKey('sheet-drag-handle'));
        final drag = await tester.startGesture(tester.getCenter(handle));
        await drag.moveBy(const Offset(0, 20));
        await drag.moveBy(const Offset(0, 220));
        await tester.pump();
        if (committed) {
          await drag.up();
        } else {
          await drag.cancel();
        }
        await tester.pump(const Duration(milliseconds: 16));
        update(() => entry = 2);
        await tester.pump();
        expect(
          tester.getTopLeft(sheet).dy,
          greaterThanOrEqualTo(600),
          reason: 'The new reader starts its own entrance without the old pull',
        );
        await tester.pumpAndSettle();
        expect(dismissed, isEmpty);
        expect(entry, 2);
        expect(find.text('Reader 2'), findsOneWidget);
        expect(tester.getRect(sheet), resting);
        await tester.pump(const Duration(milliseconds: 400));
        expect(dismissed, isEmpty);
        expect(tester.getRect(sheet), resting);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
