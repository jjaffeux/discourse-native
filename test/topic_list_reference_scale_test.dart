import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/shell/topic_list_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sidebar_filter_parity_test.dart' as fixture;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final (appScale, accessibility, height, textSize) in [
      (AppTextScale.percent100, 1.0, 44.0, 16.0),
      (AppTextScale.percent125, 2.0, 80.0, 40.0),
    ]) {
      testWidgets(
        'category header actions use reference scaling on $platform at ${appScale.factor}/$accessibility',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = accessibility;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final data = await fixture.fixture(
            tester,
            size: const Size(430, 1600),
          );
          await data.shell.appSettings.setTextScale(appScale);
          await data.shell.applyTopicListFilterQuery('category:1');
          await tester.pumpAndSettle();

          for (final key in [
            'topic-list-filter',
            'topic-list-category-filter',
            'category-notification-level-button',
          ]) {
            final control = find.byKey(ValueKey(key));
            expect(tester.getSize(control).height, height, reason: key);
            expect(
              MediaQuery.textScalerOf(tester.element(control)).scale(16),
              textSize,
              reason: key,
            );
          }
          final page = find.byType(TopicListNavigation).first;
          final content = tester.widget<TopicListNavigation>(page).child;
          expect(
            MediaQuery.textScalerOf(
              tester.element(find.byWidget(content)),
            ).scale(14),
            17 * appScale.factor * accessibility,
          );
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }
  }
}
