import 'package:discourse_native/discourse_ui.dart' show AppTextScaler;
import 'package:discourse_native/src/plugins/chat/chat_inbox.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox_filters.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sidebar_filter_parity_test.dart' as topics;
import 'support/shell_test_harness.dart' show phone;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'topic and chat filters share the mockup\'s 48-point controls on $platform',
      (tester) async {
        await topics.fixture(tester, size: phone);
        for (final key in [
          'topic-list-feed-menu',
          'topic-list-category-filter',
          'topic-list-tag-filter',
        ]) {
          expect(
            tester.getSize(find.byKey(ValueKey(key))).height,
            48,
            reason: key,
          );
        }
        final latest = find.descendant(
          of: find.byKey(const ValueKey('topic-list-feed-menu')),
          matching: find.text('Latest'),
        );
        expect(DefaultTextStyle.of(tester.element(latest)).style.fontSize, 14);
        expect(tester.takeException(), isNull);

        final filters = ChatInboxFilters();
        addTearDown(filters.dispose);
        for (final (appScale, platformScale, height) in [
          (1.0, 1.0, 48.0),
          (1.25, 2.0, 79.5),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark.copyWith(platform: platform),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: AppTextScaler(
                    platformScaler: TextScaler.linear(platformScale),
                    appScale: appScale,
                    baselineScale: 17 / 14,
                  ),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: ChatInboxFilterBar(
                  siteUrl: topics.site,
                  filters: filters,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          // Chat's switch is two marks, so its height is all it shares.
          expect(
            tester
                .getSize(find.byKey(const ValueKey('chat-inbox-sort-filter')))
                .height,
            height,
          );
          expect(tester.takeException(), isNull);
        }
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}
