import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_admin_page.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_models.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/native_ui_evidence.dart';
import 'gamification_fixture.dart';
import 'gamification_widget_support.dart';

void main() {
  Widget page(GamificationFixture f, {bool create = false, int? boardId}) =>
      GamificationAdminPage(
        site: gameSite,
        controller: f.controller,
        create: create,
        initialBoardId: boardId,
        navigation: GamificationNavigation(
          host: GamificationTestNavigationHost(),
          controller: f.controller,
        ),
      );
  for (final size in [const Size(1360, 900), const Size(390, 844)]) {
    testWidgets(
      'production admin list and management destinations at ${size.width}',
      (tester) async {
        gameSize(tester, size);
        await prepareNativeUiEvidence(tester);
        final f = GamificationFixture();
        addTearDown(f.dispose);
        await tester.pumpWidget(
          gameApp(
            page(f),
            platform: size.width < 600
                ? TargetPlatform.iOS
                : TargetPlatform.macOS,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Community champions'), findsOneWidget);
        expect(find.text('New leaderboard'), findsOneWidget);
        await captureNativeUi(
          tester,
          'gamification-admin-list-${size.width.toInt()}',
        );
        await gameTap(tester, find.text('Leaderboards'));
        await gameTap(tester, find.text('Scoring settings'));
        expect(find.text('Enable gamification'), findsOneWidget);
        expect(find.byType(DInput), findsNWidgets(15));
        await captureNativeUi(
          tester,
          'gamification-admin-settings-${size.width.toInt()}',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('new board form submits all fields and all15 override inputs', (
    tester,
  ) async {
    gameSize(tester, const Size(1200, 1000));
    final f = GamificationFixture();
    addTearDown(f.dispose);
    await tester.pumpWidget(gameApp(page(f, create: true)));
    await tester.pumpAndSettle();
    expect(find.byType(DInput), findsNWidgets(16));
    expect(find.byType(DMultiSelect<int>), findsNWidgets(3));
    await gameEnter(tester, 'Name', 'Weekend contest');
    await gameEnter(tester, 'Likes given', '0');
    await gameTap(tester, find.text('Save'));
    expect(f.transport.writes.map((r) => r.method), ['POST', 'PUT']);
    final body = f.transport.writes.last.body;
    expect(body['name'], 'Weekend contest');
    expect(body['score_overrides'], {'like_given': 0});
    expect(body['visible_to_groups_ids'], <int>[]);
    expect(body['period_filter_disabled'], false);
    expect(find.text('Weekend contest'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'deep linked edit uses detail and preserves draft after422 then saves full PUT',
    (tester) async {
      gameSize(tester, const Size(1200, 1000));
      final f = GamificationFixture();
      addTearDown(f.dispose);
      await tester.pumpWidget(gameApp(page(f, boardId: 1)));
      await tester.pumpAndSettle();
      expect(
        f.transport.reads.any(
          (r) =>
              r.path ==
              '/admin/plugins/discourse-gamification/leaderboards/1.json',
        ),
        isTrue,
      );
      await gameEnter(tester, 'Name', 'Changed contest');
      f
              .transport
              .failures['PUT /admin/plugins/gamification/leaderboard/1.json'] =
          const WriteException(
            WriteFailure.validation,
            errors: ['Server rejected dates'],
          );
      await gameTap(tester, find.text('Save'));
      expect(find.text('Server rejected dates'), findsOneWidget);
      expect(
        tester.widget<EditableText>(gameInput('Name')).controller.text,
        'Changed contest',
      );
      await gameTap(tester, find.text('Save'));
      expect(f.boards.single['name'], 'Changed contest');
      expect(f.transport.writes.every((r) => r.method == 'PUT'), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'delete requires confirmation and moderator loses all management UI',
    (tester) async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      await tester.pumpWidget(gameApp(page(f)));
      await tester.pumpAndSettle();
      await gameTap(tester, find.text('Delete'));
      expect(f.transport.writes, isEmpty);
      await gameTap(tester, find.text('Cancel'));
      expect(f.boards, hasLength(1));
      await gameTap(tester, find.text('Delete'));
      await gameTap(tester, find.text('Delete').last);
      expect(f.boards, isEmpty);
      expect(f.transport.writes.single.method, 'DELETE');
      expect(
        find.text(
          'No leaderboards yet. Create a leaderboard to make a default available.',
        ),
        findsOneWidget,
      );
      f.user = const DiscourseUser(username: 'moderator', id: 88, staff: true);
      f.controller.pluginCurrentUserRefreshed(gameSite);
      await tester.pumpAndSettle();
      expect(
        find.text('Only administrators can manage gamification.'),
        findsOneWidget,
      );
      expect(find.text('New leaderboard'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('permission change retires an open editor before save', (
    tester,
  ) async {
    final f = GamificationFixture();
    addTearDown(f.dispose);
    await tester.pumpWidget(gameApp(page(f, create: true)));
    await tester.pumpAndSettle();
    await gameEnter(tester, 'Name', 'Private draft');
    f.user = const DiscourseUser(username: 'member', id: 88);
    f.controller.pluginCurrentUserRefreshed(gameSite);
    await tester.pumpAndSettle();
    expect(find.byType(DInput), findsNothing);
    expect(f.transport.writes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Native date, group, period, category and all rule callbacks produce complete configuration',
    (tester) async {
      gameSize(tester, const Size(1200, 1000));
      final f = GamificationFixture();
      addTearDown(f.dispose);
      await tester.pumpWidget(gameApp(page(f, create: true)));
      await tester.pumpAndSettle();
      await gameEnter(tester, 'Name', 'Complete contest');
      final dates = tester
          .widgetList<DDatePicker>(find.byType(DDatePicker))
          .toList();
      dates[0].onChanged!(DCalendarDate(2026, 10, 1));
      dates[1].onChanged!(DCalendarDate(2026, 12, 1));
      final groups = tester
          .widgetList<DMultiSelect<int>>(find.byType(DMultiSelect<int>))
          .toList();
      groups[0].onChanged!([0]);
      groups[1].onChanged!([10]);
      groups[2].onChanged!([0]);
      tester
          .widget<DSelect<GamificationPeriod>>(
            find.byType(DSelect<GamificationPeriod>),
          )
          .onChanged!(GamificationPeriod.weekly);
      tester.widget<DToggle>(find.byType(DToggle)).onPressedChanged!(true);
      tester
          .widget<DCombobox<int>>(find.byType(DCombobox<int>))
          .onValuesChanged!([4, 5], DComboboxChangeReason.itemPress);
      await tester.pumpAndSettle();
      for (final label in [
        'Likes given',
        'Likes received',
        'Solutions',
        'Users invited',
        'Time reading',
        'Posts read',
        'Topics created',
        'Posts created',
        'Flags created',
        'Days visited',
        'Reactions received',
        'Reactions given',
        'Chat reactions received',
        'Chat reactions given',
        'Chat messages created',
      ]) {
        await gameEnter(tester, label, '0');
      }
      await gameTap(tester, find.text('Save'));
      final body = f.transport.writes.last.body;
      expect(body['from_date'], '2026-10-01');
      expect(body['to_date'], '2026-12-01');
      expect(body['visible_to_groups_ids'], [0]);
      expect(body['included_groups_ids'], [10]);
      expect(body['excluded_groups_ids'], [0]);
      expect(body['default_period'], 4);
      expect(body['period_filter_disabled'], true);
      expect(body['scorable_category_ids'], [4, 5]);
      expect(body['score_overrides'], {
        'like_given': 0,
        'like_received': 0,
        'solution': 0,
        'user_invited': 0,
        'time_read': 0,
        'post_read': 0,
        'topic_created': 0,
        'post_created': 0,
        'flag_created': 0,
        'day_visited': 0,
        'reaction_received': 0,
        'reaction_given': 0,
        'chat_reaction_received': 0,
        'chat_reaction_given': 0,
        'chat_message_created': 0,
      });
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'a previously rendered save callback cannot write after account lease retirement',
    (tester) async {
      final f = GamificationFixture();
      addTearDown(f.dispose);
      await tester.pumpWidget(gameApp(page(f, create: true)));
      await tester.pumpAndSettle();
      await gameEnter(tester, 'Name', 'Account A draft');
      final callback = tester
          .widget<DButton>(find.widgetWithText(DButton, 'Save'))
          .onPressed!;
      f.requests.forget(gameSite);
      f.controller.forget(gameSite);
      callback();
      await tester.pumpAndSettle();
      expect(f.transport.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
