import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_controller.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_models.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_score_events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/native_ui_evidence.dart';
import 'gamification_fixture.dart';
import 'gamification_widget_support.dart';

void main() {
  testWidgets('inspector filters exact ID and user and has no delete control', (
    tester,
  ) async {
    gameSize(tester, const Size(1360, 900));
    await prepareNativeUiEvidence(tester);
    final f = GamificationFixture();
    addTearDown(f.dispose);
    f
            .transport
            .responders['GET /admin/plugins/gamification/score_events.json?id=1&user_id=88'] =
        (_) => {'events': f.events};
    final h = f.controller.acquireAdmin(gameSite);
    addTearDown(h.release);
    await h.refresh();
    await tester.pumpWidget(
      gameApp(
        ListenableBuilder(
          listenable: h,
          builder: (context, _) => GamificationScoreEvents(handle: h),
        ),
        scroll: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Manual adjustment'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    await captureNativeUi(tester, 'gamification-admin-events-desktop');
    await gameEnter(tester, 'Event ID', '1');
    await gameEnter(tester, 'User ID', '88');
    await gameTap(tester, find.text('Filter events'));
    expect(
      f.transport.reads.last.path,
      '/admin/plugins/gamification/score_events.json?id=1&user_id=88',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'create signed event closes after confirmed POST even if list refresh fails',
    (tester) async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final h = f.controller.acquireAdmin(gameSite);
      addTearDown(h.release);
      await h.refresh();
      await tester.pumpWidget(
        gameApp(
          ListenableBuilder(
            listenable: h,
            builder: (context, _) => GamificationScoreEvents(handle: h),
          ),
          scroll: true,
        ),
      );
      await tester.pumpAndSettle();
      await gameTap(tester, find.text('New score event'));
      await gameEnter(tester, 'User ID', '88');
      await gameEnter(tester, 'Points', '-20');
      f
              .transport
              .failures['GET /admin/plugins/gamification/score_events.json'] =
          Exception('Readback unavailable');
      await gameTap(tester, find.text('Save'));
      await tester.pumpAndSettle();
      expect(f.transport.writes.single.method, 'POST');
      expect(f.events.last['points'], -20);
      expect(h.mutation.status, GamificationMutationStatus.saved);
      expect(find.text('Save'), findsNothing);
      expect(find.text('New score event'), findsOneWidget);
      expect(h.lastCreatedEvent!.id, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('edit keeps user/date immutable and clear category sends blank', (
    tester,
  ) async {
    final f = GamificationFixture();
    addTearDown(f.dispose);
    final h = f.controller.acquireAdmin(gameSite);
    addTearDown(h.release);
    await h.refresh();
    await h.queryEvents(const ScoreEventQuery());
    final original = h.events!.first;
    await tester.pumpWidget(
      gameApp(
        ListenableBuilder(
          listenable: h,
          builder: (context, _) => GamificationScoreEventEditor(
            handle: h,
            event: original,
            onFinished: () {},
          ),
        ),
        scroll: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(gameInput('User ID')).readOnly, isTrue);
    expect(
      tester.widget<DDatePicker>(find.byType(DDatePicker)).enabled,
      isFalse,
    );
    await gameTap(tester, find.text('Clear category'));
    await gameEnter(tester, 'Points', '0');
    await gameTap(tester, find.text('Save'));
    expect(f.transport.writes.single.body, {
      'id': 1,
      'points': 0,
      'description': 'Manual adjustment',
      'category_id': '',
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
