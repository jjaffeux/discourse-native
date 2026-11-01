import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_data.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_decoration.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_directory.dart';
import 'package:discourse_native/src/plugins/cakeday/cakeday_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'cakeday_fixture.dart';

Widget frame(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: child),
);
void main() {
  testWidgets(
    'birthday editor holds invalid draft without authorizing clear and can recover',
    (tester) async {
      var value = CakedayPreferences(CakedayBirthday.create(1, 30));
      final edits = <CakedayPreferences>[];
      await tester.pumpWidget(
        frame(
          StatefulBuilder(
            builder: (context, setState) => CakedayBirthdayEditor(
              value: value,
              editable: true,
              onChanged: (next) {
                edits.add(next);
                setState(() => value = next);
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('cakeday-birthday-day')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('31').last);
      await tester.pumpAndSettle();
      expect(value.payload, {'date_of_birth': '1904-1-31'});
      await tester.tap(find.byKey(const ValueKey('cakeday-birthday-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('April').last);
      await tester.pumpAndSettle();
      expect(find.text('Choose a valid month and day.'), findsOneWidget);
      expect(value.available, isTrue);
      expect(value.valid, isFalse);
      expect(value.payload, isEmpty);
      expect(find.text('April'), findsOneWidget);
      expect(find.text('31'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cakeday-birthday-day')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30').last);
      await tester.pumpAndSettle();
      expect(value.payload, {'date_of_birth': '1904-4-30'});
      await tester.tap(find.text('Clear birthday'));
      await tester.pumpAndSettle();
      expect(value.payload, {'date_of_birth': ''});
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('unavailable birthday cannot send an empty write', (
    tester,
  ) async {
    final edits = <CakedayPreferences>[];
    await tester.pumpWidget(
      frame(
        CakedayBirthdayEditor(
          value: const CakedayPreferences.unavailable(),
          editable: true,
          onChanged: edits.add,
        ),
      ),
    );
    expect(
      find.text(
        'Your birthday could not be loaded. Refresh preferences before editing it.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<DButton>(find.widgetWithText(DButton, 'Clear birthday'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<DSelect<int>>(
            find.byKey(const ValueKey('cakeday-birthday-month')),
          )
          .enabled,
      isFalse,
    );
    expect(edits, isEmpty);
  });
  testWidgets(
    'both celebrations coexist, use self/other semantics and update after privacy/settings change',
    (tester) async {
      final f = CakedayFixture();
      addTearDown(f.dispose);
      final dates = CakedayDates.read({
        'cakedate': '2020-11-01',
        'birthdate': '1992-11-01',
      })!;
      await tester.pumpWidget(
        frame(
          CakedayDecoration(
            controller: f.controller,
            site: cakedaySite,
            dates: dates,
            userId: 7,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DTooltip), findsNWidgets(2));
      expect(
        find.byWidgetPredicate(
          (w) => w is DTooltip && w.message == 'Today is your birthday!',
        ),
        findsOneWidget,
      );
      f.config.value = SiteConfig(
        emojiEnabled: false,
        plugins: PluginData.none.withValue(
          cakedaySettingsKey,
          const CakedaySettings(enabled: true, birthdays: false),
        ),
      );
      await tester.pump();
      expect(find.byType(DTooltip), findsOneWidget);
      f.user = null;
      f.controller.pluginCurrentUserRefreshed(cakedaySite);
      await tester.pump();
      expect(find.byType(DTooltip), findsNothing);
      f.controller.setForeground(false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'production directory fits $width and exposes retry then empty state',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final f = CakedayFixture();
        addTearDown(f.dispose);
        f
                .transport
                .failures['GET /cakeday/birthdays.json?page=0&filter=today'] =
            const WriteException(WriteFailure.unreachable);
        f
                .transport
                .responders['GET /cakeday/birthdays.json?page=0&filter=today'] =
            (_) => page([]);
        await tester.pumpWidget(
          frame(
            CakedayDirectory(
              site: cakedaySite,
              query: birthdayQuery,
              controller: f.controller,
              navigation: f.navigation,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Celebrations could not be loaded. Try again.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.text('No birthdays today.'), findsOneWidget);
        await tester.tap(find.text('All').last);
        await tester.pumpAndSettle();
        expect(f.routes.currentContent!.id, 'cakeday/birthdays/all/11');
        expect(tester.takeException(), isNull);
        f.controller.setForeground(false);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'preference editor clears partial local state when account identity changes',
    (tester) async {
      final settings = PluginData.none.withValue(
        cakedaySettingsKey,
        const CakedaySettings(enabled: true, birthdays: true),
      );
      Widget editor(String site, String username) => frame(
        Builder(
          builder: (context) => cakedayPreferenceSectionFor(
            context,
            PluginUserPreferenceContext(
              siteUrl: site,
              preferences: UserPreferences(
                username: username,
                canEdit: true,
                pluginValues: {
                  cakedayPreferenceSection.id: const CakedayPreferences(null),
                },
              ),
              siteSettings: settings,
              currentUserData: PluginData.none,
              currentUserIsAdmin: false,
              editable: true,
              onEdit: (_, _) {},
            ),
          )!.content,
        ),
      );
      await tester.pumpWidget(editor(cakedaySite, 'first'));
      await tester.tap(find.byKey(const ValueKey('cakeday-birthday-month')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('April').last);
      await tester.pumpAndSettle();
      expect(find.text('April'), findsOneWidget);
      await tester.pumpWidget(editor(cakedaySite, 'second'));
      await tester.pumpAndSettle();
      expect(find.text('April'), findsNothing);
      await tester.pumpWidget(editor('https://other.example', 'second'));
      await tester.pumpAndSettle();
      expect(find.text('April'), findsNothing);
    },
  );
  testWidgets(
    'retry after a failed refresh repeats page zero while keeping existing rows',
    (tester) async {
      final f = CakedayFixture();
      addTearDown(f.dispose);
      const path = 'GET /cakeday/birthdays.json?page=0&filter=today';
      f.transport.responders[path] = (_) => page([celebration(1)]);
      await tester.pumpWidget(
        frame(
          CakedayDirectory(
            site: cakedaySite,
            query: birthdayQuery,
            controller: f.controller,
            navigation: f.navigation,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('member1'), findsOneWidget);
      f.transport.failures[path] = const WriteException(
        WriteFailure.unreachable,
      );
      await f.controller.load(cakedaySite, birthdayQuery, refresh: true);
      await tester.pumpAndSettle();
      expect(find.text('member1'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      f.transport.responders[path] = (_) => page([celebration(3)]);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('member3'), findsOneWidget);
      expect(find.text('member1'), findsNothing);
      expect(
        f.transport.reads.map((r) => r.path),
        List.filled(3, '/cakeday/birthdays.json?page=0&filter=today'),
      );
      f.controller.setForeground(false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'birthday endpoint unavailability removes only birthday decoration',
    (tester) async {
      final f = CakedayFixture();
      addTearDown(f.dispose);
      final dates = CakedayDates.read({
        'cakedate': '2020-11-01',
        'birthdate': '1992-11-01',
      })!;
      await tester.pumpWidget(
        frame(
          CakedayDecoration(
            controller: f.controller,
            site: cakedaySite,
            dates: dates,
            userId: 7,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DTooltip), findsNWidgets(2));
      f.transport.failures['GET /cakeday/birthdays.json?page=0&filter=today'] =
          const WriteException(WriteFailure.validation, statusCode: 404);
      await f.controller.load(cakedaySite, birthdayQuery);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DTooltip && widget.message == 'Today is your birthday!',
        ),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DTooltip &&
              widget.message ==
                  'Today is the anniversary of the day you joined our community!',
        ),
        findsOneWidget,
      );
      f.controller.setForeground(false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'directory name priority follows member identity settings rather than post settings',
    (tester) async {
      final f = CakedayFixture();
      addTearDown(f.dispose);
      f.config.value = SiteConfig(
        prioritizeUsernameInUx: false,
        displayNameOnPosts: false,
        plugins: PluginData.none.withValue(
          cakedaySettingsKey,
          const CakedaySettings(enabled: true, birthdays: true),
        ),
      );
      f
              .transport
              .responders['GET /cakeday/birthdays.json?page=0&filter=today'] =
          (_) => page([celebration(1)]);
      await tester.pumpWidget(
        frame(
          CakedayDirectory(
            site: cakedaySite,
            query: birthdayQuery,
            controller: f.controller,
            navigation: f.navigation,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Member 1')).dy,
        lessThan(tester.getTopLeft(find.text('member1')).dy),
      );
      f.controller.setForeground(false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
