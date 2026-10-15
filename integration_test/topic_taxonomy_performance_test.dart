import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/sidebar_filter_parity_test.dart' as vocabulary;
import '../test/support/fakes.dart';
import '../test/support/shell_test_harness.dart' show primaryMainContent;

Finder get _list => find.byType(DCommandList<String>);
Finder get _field => find.byKey(const ValueKey('topic-filter-input'));
Finder _choice(String label) =>
    find.descendant(of: _list, matching: find.text(label));
int _resultCount(WidgetTester tester) => tester
    .widget<DCommandList<String>>(_list)
    .children
    .whereType<DCommandGroup<String>>()
    .fold(0, (count, group) => count + group.items.length);

Set<String> _appliedTags(ShellController shell) {
  final content = shell.topicListContent!;
  // Single tags use a route; compound matches remain in the filter query.
  final applied = '${content.topicFilterQuery} ${content.tagNames.join(' ')}';
  return RegExp(
    r'\btag-\d{3}\b',
  ).allMatches(applied).map((match) => match.group(0)!).toSet();
}

void main() {
  const touchOnly = bool.fromEnvironment('TAXONOMY_TOUCH_ONLY');
  const tagCount = int.fromEnvironment('TAXONOMY_TAG_COUNT', defaultValue: 500);
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('profiles topic category and tag dropdowns', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final messenger = binding.defaultBinaryMessenger;
    const keyboard = MethodChannel('org.discourse.native/keyboard');
    const notifications = MethodChannel(
      'org.discourse.native/notification_opens',
    );
    messenger.setMockMethodCallHandler(
      keyboard,
      (_) async => throw MissingPluginException(),
    );
    messenger.setMockMethodCallHandler(notifications, (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(keyboard, null);
      messenger.setMockMethodCallHandler(notifications, null);
    });
    debugPrint('TAXONOMY_SETUP loading shaders');
    await LiquidGlassShaders.ensureLoaded();
    debugPrint('TAXONOMY_SETUP loading fonts');
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
    final categories = List.generate(
      250,
      (i) => TopicCategory(
        id: i + 1,
        name: 'Category ${i.toString().padLeft(3, '0')}',
        slug: 'category-$i',
        color: '3188CC',
        topicCount: i + 1,
      ),
    );
    final tags = List.generate(
      tagCount,
      (i) => SidebarTag(
        id: i + 1,
        name: 'tag-${i.toString().padLeft(3, '0')}',
        slug: 'tag-$i',
        count: tagCount - i,
      ),
    );
    final api = FakeDiscourseApi(
      user: vocabulary.user,
      categoryList: categories,
      categorySiteTopTags: tags,
      siteConfigs: const {vocabulary.site: vocabulary.config},
      feeds: const {'/latest.json': [], '/filter.json': []},
      filterOptionsByPath: const {'/filter.json': vocabulary.filterMenuOptions},
    );
    debugPrint('TAXONOMY_SETUP mounting shell');
    await tester.pumpWidget(
      DiscourseApp(
        store: FakeInstanceStore([
          instance(
            'meta.discourse.org',
          ).copyWith(user: vocabulary.user, config: vocabulary.config),
        ]),
        api: api,
        authenticator: FakeAuthenticator()..keys[vocabulary.site] = 'key',
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
        initialRootMode: ShellRootMode.forum,
      ),
    );
    await tester.pumpAndSettle();
    debugPrint('TAXONOMY_SETUP shell ready');
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      await const MethodChannel(
        'org.discourse.native/window',
      ).invokeMethod<void>('dismissLaunchScreen');
    }
    final shell = ShellScope.read(tester.element(primaryMainContent));
    await Future<void>.delayed(const Duration(seconds: 2));

    var details = <String, Object>{};
    Future<void> measure(
      String component,
      DAppearanceMaterial material,
      String phase,
      Future<void> Function() action,
    ) async {
      final frames = <ui.FrameTiming>[];
      details = {};
      void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
      binding.addTimingsCallback(collect);
      final startUs = Timeline.now;
      late final int endUs;
      try {
        await action();
        endUs = Timeline.now;
        await Future<void>.delayed(const Duration(milliseconds: 600));
      } finally {
        binding.removeTimingsCallback(collect);
      }
      frames.removeWhere((frame) {
        final start = frame.timestampInMicroseconds(ui.FramePhase.buildStart);
        return start < startUs || start > endUs;
      });
      expect(frames, isNotEmpty);
      if (phase == 'scroll') expect(frames.length, greaterThan(100));
      Map<String, Object> summary(Duration Function(ui.FrameTiming) duration) {
        final values =
            frames.map((f) => duration(f).inMicroseconds / 1000).toList()
              ..sort();
        return {
          'p50Ms': values[(values.length * .50).floor()],
          'p95Ms': values[(values.length * .95).floor()],
          'p99Ms': values[(values.length * .99).floor()],
          'maxMs': values.last,
          'over16ms': values.where((ms) => ms > 16.667).length,
          'over8ms': values.where((ms) => ms > 8.333).length,
        };
      }

      final report = {
        'label': const String.fromEnvironment(
          'PROFILE_LABEL',
          defaultValue: 'current',
        ),
        'platform': defaultTargetPlatform.name,
        'debug': kDebugMode,
        'shaderFilters': ui.ImageFilter.isShaderFilterSupported,
        'shadersLoaded': LiquidGlassShaders.isLoaded,
        'logicalWidth':
            tester.view.physicalSize.width / tester.view.devicePixelRatio,
        'logicalHeight':
            tester.view.physicalSize.height / tester.view.devicePixelRatio,
        'pixelRatio': tester.view.devicePixelRatio,
        'component': component,
        'material': shell.forumSettings.shared
            .materialFor(defaultTargetPlatform)
            .name,
        'requestedMaterial': material.name,
        'phase': phase,
        'categories': categories.length,
        'tags': tags.length,
        'mountedTagCheckboxes': find
            .descendant(of: _list, matching: find.byType(DCheckbox))
            .evaluate()
            .length,
        'elapsedMs': (endUs - startUs) / 1000,
        'frames': frames.length,
        'build': summary((f) => f.buildDuration),
        'raster': summary((f) => f.rasterDuration),
        ...details,
      };
      debugPrint('TAXONOMY_PROFILE ${jsonEncode(report)}', wrapWidth: 4096);
      binding.reportData ??= {};
      binding.reportData!['${component}_${material.name}_$phase'] = report;
      expect(tester.takeException(), isNull);
    }

    Future<void> open(String component) async {
      await tester.tap(find.byKey(ValueKey('topic-list-$component-filter')));
      await tester.pumpAndSettle();
      expect(_list, findsOneWidget);
      if (defaultTargetPlatform == TargetPlatform.iOS && !touchOnly) {
        await tester.drag(
          find.byKey(const ValueKey('sheet-drag-handle')),
          const Offset(0, -350),
        );
        await tester.pumpAndSettle();
      }
    }

    Future<void> close(String component) async {
      if (component == 'tag') {
        await tester.tap(find.byKey(const ValueKey('topic-filter-done-tags')));
      } else {
        await tester.tap(_choice('Category 000'));
      }
      await tester.pumpAndSettle();
      expect(_list, findsNothing);
      if (component == 'category') {
        expect(shell.topicListContent!.categoryId, 1);
      }
      await shell.applyTopicListFilterQuery('');
      await tester.pumpAndSettle();
    }

    for (final material in DAppearanceMaterial.values) {
      await shell.forumSettings.setShared(SharedAppearance(material: material));
      await tester.pumpAndSettle();
      for (final component in touchOnly ? ['tag'] : ['category', 'tag']) {
        await measure(component, material, 'open', () => open(component));
        final initialResults = _resultCount(tester);
        expect(
          initialResults,
          greaterThanOrEqualTo(
            component == 'tag' ? tags.length : categories.length,
          ),
        );
        final results = find.descendant(
          of: _list,
          matching: find.byType(Scrollable),
        );
        expect(results, findsOneWidget);
        final position = tester.state<ScrollableState>(results).position;
        expect(position.maxScrollExtent, greaterThan(3000));
        if (touchOnly) {
          await measure(component, material, 'touch-expand', () async {
            await tester.timedDrag(
              results,
              const Offset(0, -300),
              const Duration(milliseconds: 600),
              frequency: 120,
            );
            await tester.pumpAndSettle();
          });
          // Measure content movement after the sheet's expansion gesture.
          position.jumpTo(1000);
          await tester.pumpAndSettle();
          final point = tester.getCenter(results);
          final records = <PointerEventRecord>[
            PointerEventRecord(Duration.zero, [
              PointerAddedEvent(position: point, viewId: tester.view.viewId),
              PointerDownEvent(
                position: point,
                pointer: 31,
                viewId: tester.view.viewId,
              ),
            ]),
          ];
          var previous = point;
          for (var frame = 1; frame <= 360; frame++) {
            final step = frame % 120;
            final y = step < 30
                ? -step * 4.0
                : step < 90
                ? (step - 60) * 4.0
                : (120 - step) * 4.0;
            final next = point + Offset(0, y);
            final time = Duration(microseconds: frame * 1000000 ~/ 120);
            records.add(
              PointerEventRecord(time, [
                PointerMoveEvent(
                  position: next,
                  delta: next - previous,
                  timeStamp: time,
                  pointer: 31,
                  viewId: tester.view.viewId,
                ),
              ]),
            );
            previous = next;
          }
          records.add(
            PointerEventRecord(const Duration(seconds: 3), [
              PointerCancelEvent(
                position: previous,
                pointer: 31,
                viewId: tester.view.viewId,
              ),
            ]),
          );
          await measure(component, material, 'touch-drag', () async {
            var minimum = position.pixels;
            var maximum = minimum;
            void moved() {
              if (position.pixels < minimum) minimum = position.pixels;
              if (position.pixels > maximum) maximum = position.pixels;
            }

            position.addListener(moved);
            late final List<Duration> lateEvents;
            try {
              lateEvents = await tester.handlePointerEventRecord(records);
            } finally {
              position.removeListener(moved);
            }
            expect(maximum - minimum, greaterThan(200));
            final lateness =
                lateEvents.map((d) => d.inMicroseconds / 1000).toList()..sort();
            details = {
              'inputLatenessP95Ms': lateness[(lateness.length * .95).floor()],
              'inputLatenessMaxMs': lateness.last,
              'scrollTravel': maximum - minimum,
            };
            await tester.pumpAndSettle();
          });
          await measure(component, material, 'touch-fling', () async {
            for (var repeat = 0; repeat < 3; repeat++) {
              final before = position.pixels;
              await tester.fling(results, const Offset(0, -250), 2000);
              await tester.pumpAndSettle();
              expect(position.pixels, greaterThan(before + 250));
            }
          });
          position.jumpTo(0);
          await tester.pumpAndSettle();
          await tester.tap(_choice('tag-000'));
          await tester.pumpAndSettle();
          await close(component);
          continue;
        }
        Future<void> sweep() async {
          await position.animateTo(
            1500,
            duration: const Duration(seconds: 1),
            curve: Curves.linear,
          );
          expect(
            position.pixels,
            closeTo(1500, 1),
            reason:
                'Scroll interrupted: activity=${position.activity} extent=${position.maxScrollExtent}',
          );
          await position.animateTo(
            100,
            duration: const Duration(seconds: 1),
            curve: Curves.linear,
          );
          expect(position.pixels, closeTo(100, 1));
        }

        await sweep();
        await measure(component, material, 'scroll', () async {
          final elapsed = Stopwatch()..start();
          for (var repeat = 0; repeat < 3; repeat++) {
            await sweep();
          }
          expect(
            elapsed.elapsed,
            lessThan(const Duration(seconds: 10)),
            reason: 'Reject captures interrupted by sleep or a paused target.',
          );
        });
        position.jumpTo(0);
        await tester.pumpAndSettle();
        if (defaultTargetPlatform == TargetPlatform.macOS) {
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          await measure(component, material, 'hover', () async {
            final rect = tester.getRect(results);
            final controller = tester
                .widget<DCommand<String>>(find.byType(DCommand<String>))
                .controller!;
            var changes = 0;
            String? previous;
            for (var step = 0; step < 90; step++) {
              final index = step % (component == 'tag' ? 3 : 6);
              final target = _choice(
                component == 'tag'
                    ? 'tag-${index.toString().padLeft(3, '0')}'
                    : 'Category ${index.toString().padLeft(3, '0')}',
              );
              final point = tester.getCenter(target);
              expect(rect.contains(point), isTrue);
              await mouse.moveTo(point);
              await Future<void>.delayed(const Duration(milliseconds: 17));
              if (controller.value != previous) changes++;
              previous = controller.value;
            }
            expect(
              changes,
              greaterThan(60),
              reason: 'Hover must actually change highlighted rows.',
            );
          });
          await mouse.removePointer();
        }
        await measure(component, material, 'search', () async {
          for (final query in [
            component == 'tag' ? 'tag-0' : 'Category 0',
            '',
            component == 'tag' ? 'tag-01' : 'Category 01',
            '',
          ]) {
            await tester.enterText(_field, query);
            await tester.pumpAndSettle();
            expect(
              _resultCount(tester),
              query.isEmpty
                  ? initialResults
                  : allOf(greaterThan(0), lessThan(initialResults)),
            );
          }
        });
        if (component == 'tag') {
          final selected = <String>{};
          await measure(component, material, 'select', () async {
            for (final name in ['tag-000', 'tag-001', 'tag-000', 'tag-002']) {
              await tester.tap(_choice(name));
              await tester.pumpAndSettle();
              if (!selected.add(name)) selected.remove(name);
              expect(_appliedTags(shell), unorderedEquals(selected));
              expect(_list, findsOneWidget);
            }
          });
          await measure(component, material, 'match-mode', () async {
            for (final label in ['All', 'None', 'Not all', 'Any']) {
              await tester.tap(find.widgetWithText(DToggle, label));
              await tester.pumpAndSettle();
              expect(_list, findsOneWidget);
              expect(_appliedTags(shell), unorderedEquals(selected));
            }
          });
        }
        await measure(component, material, 'close', () => close(component));
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
