import 'dart:async';
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_controller.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_recalculation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/native_ui_evidence.dart';
import 'gamification_fixture.dart';
import 'gamification_widget_support.dart';

void main() {
  test(
    'completion is scoped to literal channel, site, requester and captured account',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final channels = RecordingPluginLiveChannels();
      f.controller.attachPluginTracker(gameSite, channels);
      final h = f.controller.acquireAdmin(gameSite);
      addTearDown(h.release);
      await h.refresh();
      expect(channels.channels, ['/recalculate_scores']);
      await h.recalculate(DCalendarDate(2014, 8, 26));
      expect(h.recalculation, isA<RecalculationQueued>());
      channels.deliver('/recalculate_scores', {
        'success': true,
        'remaining': 4,
        'user_id': [9],
      });
      expect(h.recalculation, isA<RecalculationQueued>());
      channels.deliver('/recalculate_scores', {
        'success': true,
        'remaining': 4,
        'user_id': [88],
      });
      expect(h.recalculation, isA<RecalculationObserved>());
      await gameFlush();
      expect(h.index!.recalculationsRemaining, 4);
      await h.recalculate(DCalendarDate(2026, 10, 30));
      f.requests.forget(gameSite);
      channels.deliver('/recalculate_scores', {
        'success': true,
        'user_id': [88],
      });
      expect(h.recalculation, isA<RecalculationQueued>());
      h.release();
      expect(channels.subscriberCount('/recalculate_scores'), 0);
    },
  );
  test('matching completion before enqueue response is retained', () async {
    final f = GamificationFixture();
    addTearDown(f.dispose);
    final channels = RecordingPluginLiveChannels();
    f.controller.attachPluginTracker(gameSite, channels);
    final h = f.controller.acquireAdmin(gameSite);
    addTearDown(h.release);
    await h.refresh();
    final pending = Completer<Map<String, dynamic>>();
    f
            .transport
            .responders['PUT /admin/plugins/gamification/recalculate-scores.json'] =
        (_) => pending.future;
    final result = h.recalculate(DCalendarDate(2014, 8, 26));
    await gameFlush();
    expect(h.recalculation, isA<RecalculationSubmitting>());
    channels.deliver('/recalculate_scores', {
      'success': true,
      'user_id': [88],
      'remaining': 4,
    });
    expect(h.recalculation, isA<RecalculationObserved>());
    pending.complete({'success': true});
    expect((await result).status, GamificationMutationStatus.saved);
    expect(h.recalculation, isA<RecalculationObserved>());
    expect(h.busy, isFalse);
  });
  test(
    'background and reconnect preserve honest unknown completion; account retirement clears it',
    () async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final channels = RecordingPluginLiveChannels();
      f.controller.attachPluginTracker(gameSite, channels);
      final h = f.controller.acquireAdmin(gameSite);
      addTearDown(h.release);
      await h.refresh();
      await h.recalculate(DCalendarDate(2014, 8, 26));
      f.controller.setForeground(false);
      expect(h.recalculation, isA<RecalculationUnknown>());
      expect(channels.channels, isEmpty);
      f.controller.setForeground(true);
      await gameFlush();
      channels.deliver('/recalculate_scores', {
        'success': true,
        'user_id': [88],
      });
      expect(h.recalculation, isA<RecalculationUnknown>());
      f.requests.forget(gameSite);
      f.controller.pluginCurrentUserRefreshed(gameSite);
      await gameFlush();
      expect(h.recalculation, isA<RecalculationIdle>());
    },
  );
  testWidgets(
    'presets preview cutoff and only confirmed action queues a request',
    (tester) async {
      gameSize(tester, const Size(390, 844));
      await prepareNativeUiEvidence(tester);
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final channels = RecordingPluginLiveChannels();
      f.controller.attachPluginTracker(gameSite, channels);
      final h = f.controller.acquireAdmin(gameSite);
      addTearDown(h.release);
      await h.refresh();
      await tester.pumpWidget(
        gameApp(
          ListenableBuilder(
            listenable: h,
            builder: (context, _) => GamificationRecalculation(handle: h),
          ),
          scroll: true,
          platform: TargetPlatform.iOS,
        ),
      );
      await tester.pumpAndSettle();
      await gameTap(tester, find.text('Last 10 days'));
      await gameTap(tester, find.text('All time'));
      expect(find.text('From date: 2014-08-26'), findsOneWidget);
      await captureNativeUi(tester, 'gamification-admin-recalculate-phone');
      await gameTap(tester, find.text('Recalculate scores'));
      expect(f.transport.writes, isEmpty);
      await gameTap(tester, find.text('Recalculate scores').last);
      expect(f.transport.writes.single.body, {'from_date': '2014-08-26'});
      expect(
        find.text('Queued. Waiting for a completion notice for your account.'),
        findsOneWidget,
      );
      channels.deliver('/recalculate_scores', {
        'success': true,
        'user_id': [88],
      });
      await tester.pumpAndSettle();
      expect(
        find.text(
          'A recalculation completion was observed for your account. Results are refreshing.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'exhausted allowance disables action and rate-limit errors remain typed',
    (tester) async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      f.remaining = 0;
      final h = f.controller.acquireAdmin(gameSite);
      addTearDown(h.release);
      await h.refresh();
      await tester.pumpWidget(
        gameApp(GamificationRecalculation(handle: h), scroll: true),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DButton>(find.widgetWithText(DButton, 'Recalculate scores'))
            .onPressed,
        isNull,
      );
      expect(find.text('No recalculations remaining'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      f.remaining = 1;
      await h.refresh();
      f
              .transport
              .failures['PUT /admin/plugins/gamification/recalculate-scores.json'] =
          const WriteException(WriteFailure.rateLimited, statusCode: 429);
      final result = await h.recalculate(DCalendarDate(2026, 10, 30));
      expect(result.status, GamificationMutationStatus.failed);
      expect(result.error, isA<WriteException>());
    },
  );
  testWidgets(
    'missing completion expires to unknown without retrying mutation',
    (tester) async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final channels = RecordingPluginLiveChannels();
      f.controller.attachPluginTracker(gameSite, channels);
      final h = f.controller.acquireAdmin(gameSite);
      addTearDown(h.release);
      await h.refresh();
      await h.recalculate(DCalendarDate(2014, 8, 26));
      expect(h.recalculation, isA<RecalculationQueued>());
      await tester.pump(const Duration(minutes: 5));
      expect(h.recalculation, isA<RecalculationUnknown>());
      expect(f.transport.writes, hasLength(1));
      h.release();
    },
  );
}
