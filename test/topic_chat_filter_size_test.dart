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
      'topic and chat filters share larger visible controls on $platform',
      (tester) async {
        await topics.fixture(tester, size: phone);
        for (final key in [
          'topic-list-view-switch',
          'topic-list-category-filter',
          'topic-list-tag-filter',
          'topic-list-filter',
        ]) {
          expect(
            tester.getSize(find.byKey(ValueKey(key))).height,
            44,
            reason: key,
          );
        }
        final latest = find.descendant(
          of: find.byKey(const ValueKey('topic-list-view-switch')),
          matching: find.text('Latest'),
        );
        expect(DefaultTextStyle.of(tester.element(latest)).style.fontSize, 16);
        expect(tester.takeException(), isNull);

        final filters = ChatInboxFilters();
        addTearDown(filters.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark.copyWith(platform: platform),
            home: Scaffold(
              body: ChatInboxFilterBar(siteUrl: topics.site, filters: filters),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final key in [
          'chat-inbox-activity-filter',
          'chat-inbox-sort-filter',
        ]) {
          final control = find.byKey(ValueKey(key));
          expect(tester.getSize(control).height, 44, reason: key);
          final label = find.descendant(
            of: control,
            matching: find.byType(Text),
          );
          expect(DefaultTextStyle.of(tester.element(label)).style.fontSize, 16);
        }
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}
