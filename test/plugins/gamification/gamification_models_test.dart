import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_models.dart';
import 'package:discourse_native/src/plugins/gamification/gamification_plugin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'gamification_fixture.dart';

void main() {
  test('absence, disabled and signed score fields stay distinct', () {
    const plugin = GamificationPlugin();
    expect(plugin.readSiteSettings({}, gameSite), isNull);
    expect(
      plugin.readSiteSettings({
        'discourse_gamification_enabled': false,
      }, gameSite)!.enabled,
      isFalse,
    );
    expect(
      plugin.readUserCard({'gamification_score': 0}, gameSite)!.totalScore,
      0,
    );
    expect(
      plugin.readUserCard({'gamification_score': -9}, gameSite)!.totalScore,
      -9,
    );
    expect(plugin.readUserCard({'gamification_score': '9'}, gameSite), isNull);
    const codec = GamificationSettingsCodec();
    expect(
      codec
          .decode(codec.encode(const GamificationSettings(enabled: false)))!
          .enabled,
      isFalse,
    );
    expect(codec.decode({'enabled': 'false'}), isNull);
  });
  test(
    'system creator and everyone group survive while rank IDs are positive',
    () {
      final b = GamificationAdminBoard.decode(gameBoard());
      expect(b.board.createdById, -1);
      expect(b.creator!.id, -1);
      expect(b.board.visibleToGroupIds, {0});
      expect(
        GamificationRankedUser.decode(gameUser(score: -12)).totalScore,
        -12,
      );
      expect(
        () => GamificationRankedUser.decode(gameUser(rank: 0)),
        throwsFormatException,
      );
      expect(
        () => GamificationRankedUser.decode(gameUser(id: -1)),
        throwsFormatException,
      );
      expect(
        () => GamificationLeaderboard.decode({
          ...gameBoard(),
          'default_period': 'future',
        }),
        throwsA(isA<GamificationUnsupportedResponse>()),
      );
    },
  );
  test(
    'full drafts distinguish inherited absent override from zero and clear dates',
    () {
      final draft = GamificationBoardDraft(
        name: 'Contest',
        visibleToGroupIds: {0},
        scoreOverrides: {GamificationRule.likeGiven: 0},
      );
      expect(draft.toBody(), {
        'name': 'Contest',
        'from_date': '',
        'to_date': '',
        'default_period': 0,
        'period_filter_disabled': false,
        'visible_to_groups_ids': [0],
        'included_groups_ids': <int>[],
        'excluded_groups_ids': <int>[],
        'scorable_category_ids': <int>[],
        'score_overrides': {'like_given': 0},
      });
      expect(
        GamificationBoardDraft(
          name: 'x',
          fromDate: DCalendarDate(2026, 11, 2),
          toDate: DCalendarDate(2026, 11, 1),
        ).valid,
        isFalse,
      );
      expect(() => gameDate('2026-02-30'), throwsFormatException);
      expect(() => gameDate('2026-11-01T00:00:00Z'), throwsFormatException);
    },
  );
  test(
    'preset dates use UTC civil dates and clamp calendar year subtraction',
    () {
      final leap = DateTime.utc(2024, 2, 29, 23);
      expect(
        recalculationDate(RecalculationPreset.lastYear, leap),
        DCalendarDate(2023, 2, 28),
      );
      expect(
        recalculationDate(RecalculationPreset.allTime, leap),
        DCalendarDate(2014, 8, 26),
      );
      expect(
        recalculationDate(
          RecalculationPreset.tenDays,
          DateTime.parse('2026-11-01T00:30:00+02:00'),
        ),
        DCalendarDate(2026, 10, 21),
      );
      expect(
        recalculationDate(RecalculationPreset.thirtyDays, leap),
        DCalendarDate(2024, 1, 30),
      );
      expect(
        recalculationDate(RecalculationPreset.ninetyDays, leap),
        DCalendarDate(2023, 12, 1),
      );
      expect(
        recalculationDate(
          RecalculationPreset.custom,
          leap,
          custom: DCalendarDate(2016, 1, 1),
        ),
        DCalendarDate(2016, 1, 1),
      );
    },
  );
}
