import 'package:discourse_native/src/plugins/gamification/gamification_compact.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_models.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_navigation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/native_ui_evidence.dart';
import 'gamification_fixture.dart';
import 'gamification_widget_support.dart';

void main() {
  testWidgets(
    'compact defaults to10 users and links title to resolved board with selected period',
    (tester) async {
      await prepareNativeUiEvidence(tester);
      final f = GamificationFixture();
      addTearDown(f.dispose);
      final host = GamificationTestNavigationHost();
      f
              .transport
              .responders['GET /leaderboard.json?page=0&period=weekly&user_limit=10'] =
          (_) => f.publicResponse;
      await tester.pumpWidget(
        gameApp(
          SizedBox(
            width: 500,
            child: GamificationCompact(
              site: gameSite,
              controller: f.controller,
              navigation: GamificationNavigation(
                host: host,
                controller: f.controller,
              ),
              query: const GamificationQuery(period: GamificationPeriod.weekly),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        f.transport.reads.single.path,
        '/leaderboard.json?page=0&period=weekly&user_limit=10',
      );
      expect(find.text('Your position'), findsNothing);
      expect(find.text('Load more'), findsNothing);
      await captureNativeUi(tester, 'gamification-compact-desktop');
      await gameTap(tester, find.text('Community champions'));
      expect(host.currentContent!.id, 'gamification/1?period=weekly');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
