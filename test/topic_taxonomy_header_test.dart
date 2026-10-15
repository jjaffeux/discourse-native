import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sidebar_filter_parity_test.dart' as fixture;
import 'support/shell_test_harness.dart' show desktop, phone;

void main({
  bool nativeView = false,
  Future<void> Function(WidgetTester tester, String name)? onCapture,
}) {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });
  setUpAll(() async {
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
  });
  const baking = TopicCategory(
    id: 1,
    name: 'baking',
    slug: 'product',
    color: '9760CC',
  );
  const bread = TopicCategory(
    id: 2,
    name: 'bread',
    slug: 'design',
    parentCategoryId: 1,
    color: '9760CC',
  );
  for (final platform
      in nativeView
          ? [TargetPlatform.iOS]
          : [
              TargetPlatform.macOS,
              TargetPlatform.iOS,
              TargetPlatform.linux,
              TargetPlatform.android,
            ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('selected category header $platform at $scale', (
        tester,
      ) async {
        final previousShadows = debugDisableShadows;
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = previousShadows);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final mobile =
            platform == TargetPlatform.iOS ||
            platform == TargetPlatform.android;
        final glass =
            platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
        final nativeSize = tester.view.physicalSize;
        final nativePixelRatio = tester.view.devicePixelRatio;
        final data = await fixture.fixture(
          tester,
          // The shared widget harness temporarily uses DPR 1. Keep its native
          // physical extent until restoring DPR so real safe-area pixels do
          // not consume most of a small synthetic viewport during startup.
          size: nativeView
              ? nativeSize
              : mobile
              ? phone
              : desktop,
          categories: const [baking, bread],
          filterOptions: fixture.filterMenuOptions,
        );
        if (nativeView) {
          tester.view.physicalSize = nativeSize;
          tester.view.devicePixelRatio = nativePixelRatio;
        }
        await data.shell.forumSettings.setShared(
          SharedAppearance(
            font: ForumFont.openSans,
            interfaceFont: ForumFont.openSans,
            material: glass
                ? DAppearanceMaterial.liquidGlass
                : DAppearanceMaterial.standard,
          ),
        );
        await data.shell.forumSettings.setThemeMode(
          fixture.site,
          glass ? AppThemeMode.dark : AppThemeMode.light,
        );
        await data.shell.applyTopicListFilterQuery('category:1');
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            ValueKey(
              scale == 1
                  ? 'topic-list-subcategory-filter-1'
                  : 'topic-list-category-filter',
            ),
          ),
        );
        await tester.pumpAndSettle();
        final token = find.byType(DFilterToken);
        expect(token, findsOneWidget);
        expect(find.text('Category: baking'), findsOneWidget);
        final pill = tester.getRect(token);
        final remove = tester.getRect(
          find.byKey(const ValueKey('topic-filter-token-remove-0')),
        );
        expect(remove.right, pill.right);
        expect(remove.top, pill.top);
        expect(remove.bottom, pill.bottom);
        expect(pill.height, closeTo(18 * scale + 6, .01));
        final input = find.descendant(
          of: fixture.field,
          matching: find.byType(DInput),
        );
        final query = tester.getRect(input);
        expect(tester.widget<DInput>(input).hintText, 'Search category…');
        expect(tester.widget<DInput>(input).style!.fontSize, 13);
        if (query.top < pill.bottom) {
          expect(query.center.dy, closeTo(pill.center.dy, .01));
          expect(query.left, closeTo(pill.right + 9, .01));
        } else {
          expect(query.left, closeTo(pill.left + 4, .01));
          expect(query.top, greaterThanOrEqualTo(pill.bottom + 8));
        }
        await fixture.capture(
          tester,
          'taxonomy-selected-header-$platform-$scale',
        );
        await onCapture?.call(
          tester,
          'taxonomy-selected-header-$platform-$scale',
        );
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.byKey(const ValueKey('topic-filter-token-remove-0')),
        );
        await tester.pumpAndSettle();
        expect(data.shell.topicListContent!.categoryId, isNull);
        expect(find.byType(DCommandList<String>), findsOneWidget);
        expect(find.byType(DFilterToken), findsNothing);
        debugDisableShadows = previousShadows;
      }, variant: TargetPlatformVariant.only(platform));
    }
  }
}
