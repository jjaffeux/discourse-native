import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_settings_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'gamification_fixture.dart';
import 'gamification_widget_support.dart';

void main() {
  testWidgets(
    'all18 settings save signed weights, ranking and selected categories',
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
            builder: (context, _) =>
                GamificationSettingsEditor(handle: h, settings: h.settings!),
          ),
          scroll: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DInput), findsNWidgets(15));
      await gameEnter(tester, 'Likes given', '-5');
      tester
          .widget<DCombobox<int>>(find.byType(DCombobox<int>))
          .onValuesChanged!([4, 5], DComboboxChangeReason.itemPress);
      await tester.pumpAndSettle();
      await gameTap(tester, find.text('Dense rank (1, 1, 2)'));
      await gameTap(tester, find.text('Competition rank (1, 1, 3)'));
      await gameTap(tester, find.text('Enable gamification'));
      await gameTap(tester, find.text('Save'));
      final body = f.transport.writes.single.body['settings'] as Map;
      expect(body, hasLength(18));
      expect(body['like_given_score_value'], {'value': -5});
      expect(body['scorable_categories'], {'value': '4|5'});
      expect(body['score_ranking_strategy'], {'value': 'rank'});
      expect(body['discourse_gamification_enabled'], {'value': false});
      expect(f.controller.enabled(gameSite), isFalse);
      expect(find.text('Saved.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('invalid integer settings reject locally with no mutation', (
    tester,
  ) async {
    final f = GamificationFixture(enabled: false);
    addTearDown(f.dispose);
    final h = f.controller.acquireAdmin(gameSite);
    addTearDown(h.release);
    await h.refresh();
    await tester.pumpWidget(
      gameApp(
        GamificationSettingsEditor(handle: h, settings: h.settings!),
        scroll: true,
      ),
    );
    await tester.pumpAndSettle();
    await gameEnter(tester, 'Likes given', '1.5');
    await gameTap(tester, find.text('Save'));
    expect(f.transport.writes, isEmpty);
    expect(
      find.text('Enter an integer for each scoring weight.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
