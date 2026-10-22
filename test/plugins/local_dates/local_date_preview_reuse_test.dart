import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_widget.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_module.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relative_time/relative_time.dart';

const _deadline = LocalDateSpec(
  date: '2026-01-11',
  time: '12:00:00',
  timezone: 'UTC',
  countdown: true,
  timezones: ['Asia/Tokyo', 'America/New_York'],
  fallbackText: 'fallback',
);

void main() {
  testWidgets('60 countdown ticks reuse unchanged preview semantics', (
    tester,
  ) async {
    final harness = _Harness(tester, DateTime.utc(2026, 1, 11, 11, 58));
    await harness.show(_deadline);
    final initialLabel = harness.label(_deadline);
    expect(find.bySemanticsLabel(initialLabel), findsOneWidget);
    expect(find.textContaining('2 minutes'), findsOneWidget);
    expect(harness.formatter.previewCalls, 1);

    for (var tick = 0; tick < 60; tick++) {
      await tester.pump(const Duration(seconds: 1));
      expect(find.bySemanticsLabel(initialLabel), findsOneWidget);
    }

    expect(find.textContaining('a minute'), findsOneWidget);
    expect(harness.formatter.previewCalls, 1);
  });

  testWidgets('recurring semantics advance only after the exact deadline', (
    tester,
  ) async {
    final harness = _Harness(
      tester,
      DateTime.utc(2026, 1, 11, 11, 59, 59, 750),
    );
    const spec = LocalDateSpec(
      date: '2026-01-11',
      time: '12:00:00',
      timezone: 'UTC',
      countdown: true,
      recurring: '1.minutes',
      fallbackText: 'fallback',
    );
    await harness.show(spec);
    final initialLabel = harness.label(spec);
    expect(find.bySemanticsLabel(initialLabel), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('now'), findsOneWidget);
    expect(find.bySemanticsLabel(initialLabel), findsOneWidget);
    expect(harness.formatter.previewCalls, 1);

    await tester.pump(const Duration(milliseconds: 1));
    final nextLabel = harness.label(spec);
    expect(nextLabel, isNot(initialLabel));
    expect(find.bySemanticsLabel(nextLabel), findsOneWidget);
    expect(find.textContaining('a minute'), findsOneWidget);
    expect(harness.formatter.previewCalls, 2);
  });

  testWidgets('daily recurrence refreshes previews across a DST boundary', (
    tester,
  ) async {
    final harness = _Harness(tester, DateTime.utc(2026, 3, 7, 13, 59, 59, 750));
    const spec = LocalDateSpec(
      date: '2026-03-07',
      time: '09:00:00',
      timezone: 'America/New_York',
      countdown: true,
      recurring: '1.days',
      timezones: ['Asia/Tokyo'],
      fallbackText: 'fallback',
    );
    await harness.show(spec);
    final initialLabel = harness.label(spec);
    expect(find.bySemanticsLabel(initialLabel), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 250));
    expect(find.bySemanticsLabel(initialLabel), findsOneWidget);
    expect(harness.formatter.previewCalls, 1);

    await tester.pump(const Duration(milliseconds: 1));
    final nextLabel = harness.label(spec);
    expect(nextLabel, isNot(initialLabel));
    expect(find.bySemanticsLabel(nextLabel), findsOneWidget);
    expect(
      harness.formatter.resolveInstant(spec, now: harness.now()),
      DateTime.utc(2026, 3, 8, 13),
    );
    expect(harness.formatter.previewCalls, 2);
  });

  testWidgets(
    'retained hidden countdown catches up to the current occurrence',
    (tester) async {
      final harness = _Harness(tester, DateTime.utc(2026, 1, 11, 11, 59));
      const spec = LocalDateSpec(
        date: '2026-01-11',
        time: '12:00:00',
        timezone: 'UTC',
        countdown: true,
        recurring: '1.days',
        fallbackText: 'fallback',
      );
      await harness.show(spec);
      final state = tester.state(find.byType(LocalDateInline));
      final initialLabel = harness.label(spec);
      await harness.show(spec, visible: false);
      final callsWhileHidden = harness.formatter.previewCalls;
      await tester.pump(const Duration(days: 3, hours: 1));
      expect(harness.formatter.previewCalls, callsWhileHidden);

      await harness.show(spec);
      expect(tester.state(find.byType(LocalDateInline)), same(state));
      final currentLabel = harness.label(spec);
      expect(currentLabel, isNot(initialLabel));
      expect(find.bySemanticsLabel(currentLabel), findsOneWidget);
      expect(harness.formatter.previewCalls, callsWhileHidden + 1);
    },
  );

  testWidgets(
    'locale, device zone, notification and formatter invalidate reuse',
    (tester) async {
      final harness = _Harness(tester, DateTime.utc(2026, 1, 11, 11, 58));
      await harness.show(_deadline);
      final state = tester.state(find.byType(LocalDateInline));
      final englishLabel = harness.label(_deadline);

      await harness.show(_deadline, locale: const Locale('fr'));
      final frenchLabel = harness.label(_deadline, locale: const Locale('fr'));
      expect(frenchLabel, isNot(englishLabel));
      expect(find.bySemanticsLabel(frenchLabel), findsOneWidget);
      expect(harness.formatter.previewCalls, 2);

      await harness.environment.refreshDeviceTimezone(forceNotify: true);
      await tester.pump();
      expect(find.bySemanticsLabel(frenchLabel), findsOneWidget);
      expect(harness.formatter.previewCalls, 3);

      harness.environment.setDeviceTimezone('Europe/Paris');
      await tester.pump();
      final parisLabel = harness.label(_deadline, locale: const Locale('fr'));
      expect(parisLabel, isNot(frenchLabel));
      expect(find.bySemanticsLabel(parisLabel), findsOneWidget);
      expect(harness.formatter.previewCalls, 4);

      final replacement = _CountingFormatter(environment: harness.environment);
      await harness.show(
        _deadline,
        locale: const Locale('fr'),
        formatter: replacement,
      );
      expect(tester.state(find.byType(LocalDateInline)), same(state));
      expect(find.bySemanticsLabel(parisLabel), findsOneWidget);
      expect(replacement.previewCalls, 1);
    },
  );

  testWidgets(
    'replacement specs and mutable timezone lists refresh semantics',
    (tester) async {
      final harness = _Harness(tester, DateTime.utc(2026, 1, 11, 11, 58));
      final timezones = ['Asia/Tokyo'];
      final spec = LocalDateSpec(
        date: '2026-01-11',
        time: '12:00:00',
        timezone: 'UTC',
        countdown: true,
        timezones: timezones,
        fallbackText: 'fallback',
      );
      await harness.show(spec);
      final state = tester.state(find.byType(LocalDateInline));
      final initialLabel = harness.label(spec);
      timezones[0] = 'America/New_York';
      await harness.show(spec);
      final mutatedLabel = harness.label(spec);
      expect(mutatedLabel, isNot(initialLabel));
      expect(find.bySemanticsLabel(mutatedLabel), findsOneWidget);
      expect(harness.formatter.previewCalls, 2);

      await harness.show(_deadline);
      expect(tester.state(find.byType(LocalDateInline)), same(state));
      expect(find.bySemanticsLabel(harness.label(_deadline)), findsOneWidget);
      expect(harness.formatter.previewCalls, 3);
    },
  );

  testWidgets('site defaults and account timezone refresh retained semantics', (
    tester,
  ) async {
    final harness = _Harness(tester, DateTime.utc(2026, 1, 11, 11, 58));
    final defaults = ['Asia/Tokyo'];
    var accountTimezone = 'Europe/Paris';
    final installed = PluginInstaller.install(
      PluginManifest([LocalDatesModule(environment: harness.environment)]),
    );
    final session = installed.openSession(
      PluginHostBindings([
        PluginHostPort<PluginSiteStateHost>(
          corePluginSiteStatePort,
          PluginSiteStateHost(
            currentUserFor: (_) => DiscourseUser(
              id: 1,
              username: 'reader',
              timezone: accountTimezone,
            ),
            siteConfigFor: (_) => SiteConfig(
              plugins: PluginData.none.withValue(
                localDatesSettingsDataKey,
                LocalDatesSettings(timezones: defaults),
              ),
            ),
          ),
        ),
        PluginHostPort<PluginCurrentSiteReader>(
          corePluginCurrentSitePort,
          () => 'https://forum.example',
        ),
      ]),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await session.close();
      await installed.close();
    });
    harness.wrap = (child) => PluginScope(
      session: session,
      registry: installed.registry,
      child: PluginUiScope.own(localDatesPluginId, child),
    );
    const spec = LocalDateSpec(
      date: '2026-01-11',
      time: '12:00:00',
      timezone: 'UTC',
      countdown: true,
      fallbackText: 'fallback',
    );
    String expected() => harness.label(
      spec,
      accountTimezone: accountTimezone,
      defaultTimezones: defaults,
    );
    await harness.show(spec);
    final state = tester.state(find.byType(LocalDateInline));
    final initialLabel = expected();
    expect(find.bySemanticsLabel(initialLabel), findsOneWidget);

    defaults[0] = 'America/New_York';
    await harness.show(spec);
    final defaultsLabel = expected();
    expect(defaultsLabel, isNot(initialLabel));
    expect(find.bySemanticsLabel(defaultsLabel), findsOneWidget);
    expect(harness.formatter.previewCalls, 2);

    accountTimezone = 'Australia/Brisbane';
    await harness.show(spec);
    expect(tester.state(find.byType(LocalDateInline)), same(state));
    final accountLabel = expected();
    expect(accountLabel, isNot(defaultsLabel));
    expect(find.bySemanticsLabel(accountLabel), findsOneWidget);
    expect(harness.formatter.previewCalls, 3);
  });
}

class _Harness {
  _Harness(this.tester, this.start) : clockStart = tester.binding.clock.now() {
    environment.setDeviceTimezone('Etc/UTC');
    formatter = _CountingFormatter(environment: environment);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      environment.dispose();
    });
  }

  final WidgetTester tester;
  final DateTime start;
  final DateTime clockStart;
  final environment = LocalDateEnvironment.forTesting(
    detectDeviceTimezone: () async => 'Etc/UTC',
  );
  late final _CountingFormatter formatter;
  Widget Function(Widget)? wrap;

  DateTime now() =>
      start.add(tester.binding.clock.now().difference(clockStart));

  String label(
    LocalDateSpec spec, {
    Locale locale = const Locale('en'),
    String? accountTimezone,
    Iterable<String> defaultTimezones = const [],
  }) => LocalDateFormatter(environment: environment)
      .previews(
        spec,
        locale: locale,
        accountTimezone: accountTimezone,
        defaultTimezones: defaultTimezones,
        now: now(),
      )
      .map((preview) => '${preview.label}: ${preview.formatted}')
      .join(', ');

  Future<void> show(
    LocalDateSpec spec, {
    Locale locale = const Locale('en'),
    bool visible = true,
    LocalDateFormatter? formatter,
  }) {
    final child = Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        child: LocalDateInline(
          key: const ValueKey('retained-date'),
          spec: spec,
          formatter: formatter ?? this.formatter,
          now: now,
        ),
      ),
    );
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        themeAnimationDuration: Duration.zero,
        locale: locale,
        localizationsDelegates:
            RelativeTimeLocalizations.localizationsDelegates,
        supportedLocales: RelativeTimeLocalizations.supportedLocales,
        home: Scaffold(body: wrap?.call(child) ?? child),
      ),
    );
  }
}

class _CountingFormatter extends LocalDateFormatter {
  _CountingFormatter({required super.environment});

  int previewCalls = 0;

  @override
  List<LocalDatePreview> previews(
    LocalDateSpec spec, {
    required Locale locale,
    String? accountTimezone,
    Iterable<String> defaultTimezones = const [],
    DateTime? now,
  }) {
    previewCalls++;
    return super.previews(
      spec,
      locale: locale,
      accountTimezone: accountTimezone,
      defaultTimezones: defaultTimezones,
      now: now,
    );
  }
}
