import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/foundation/timezone_environment.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/shell/preferences_page.dart';
import 'package:discourse_native/src/shell/select.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://preferences.example';
const _site = DiscourseInstance(
  url: _siteUrl,
  title: 'Preferences Forum',
  user: DiscourseUser(
    id: 7,
    username: 'reader',
    timezone: 'Etc/UTC',
    bookmarkAutoDeletePreference: BookmarkAutoDeletePreference.clearReminder,
  ),
);
const _preferences = UserPreferences(
  username: 'reader',
  timezone: 'Etc/UTC',
  likeNotificationFrequency: 1,
  notifyOnLinkedPosts: true,
  newTopicDurationMinutes: 2880,
  autoTrackTopicsAfterMsecs: 300000,
  notificationLevelWhenReplying: 2,
  bookmarkAutoDeletePreference: BookmarkAutoDeletePreference.clearReminder,
  canEdit: true,
  canChangeTrackingPreferences: true,
);

typedef _Fixture = ({
  ShellController shell,
  FakeDiscourseApi api,
  _RecordingInstanceStore store,
});

Future<_Fixture> _fixture({
  UserPreferences preferences = _preferences,
  Completer<void>? loadGate,
  Completer<void>? writeGate,
  WriteException? writeFailure,
}) async {
  final api = FakeDiscourseApi(
    user: _site.user,
    userPreferences: preferences,
    userPreferencesGate: loadGate,
    userPreferencesWriteGate: writeGate,
    writeFailure: writeFailure,
  );
  final store = _RecordingInstanceStore([_site]);
  final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
  final shell = ShellController(
    instanceStore: store,
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    ownsApi: false,
  );
  addTearDown(shell.dispose);
  await shell.load();
  store.saved.clear();
  return (shell: shell, api: api, store: store);
}

Future<void> _pumpPage(
  WidgetTester tester,
  _Fixture fixture, {
  double width = 680,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ShellScope(
      controller: fixture.shell,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 900,
            child: const PreferencesPage(siteUrl: _siteUrl),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}

Finder _save(PreferenceSection section) =>
    find.byKey(ValueKey('preferences-save-${section.name}'));

DButton _saveButton(WidgetTester tester, PreferenceSection section) =>
    tester.widget<DButton>(_save(section));

Future<void> _chooseNarrowSection(
  WidgetTester tester,
  PreferenceSection section,
) async {
  await tester.tap(
    find.byKey(
      const ValueKey(('preferences-section', PreferenceSection.notifications)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(_sectionLabel(section)).last);
  await tester.pumpAndSettle();
}

String _sectionLabel(PreferenceSection section) => switch (section) {
  PreferenceSection.notifications => 'Notifications',
  PreferenceSection.tracking => 'Tracking',
  PreferenceSection.datesAndReminders => 'Dates & reminders',
};

void main() {
  setUpAll(TimezoneEnvironment.instance.ensureDatabase);

  testWidgets('narrow and wide layouts expose the appropriate section picker', (
    tester,
  ) async {
    final fixture = await _fixture();
    await _pumpPage(tester, fixture, width: 680);

    expect(
      find.byKey(
        const ValueKey((
          'preferences-section',
          PreferenceSection.notifications,
        )),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('preferences-section-notifications')),
      findsNothing,
    );

    await _pumpPage(tester, fixture, width: 1000);

    expect(find.byType(DSelectField<PreferenceSection>), findsNothing);
    final notifications = find.byKey(
      const ValueKey('preferences-section-notifications'),
    );
    final tracking = find.byKey(const ValueKey('preferences-section-tracking'));
    expect(notifications, findsOneWidget);
    expect(tracking, findsOneWidget);
    expect(tester.getSize(notifications).height, greaterThanOrEqualTo(48));

    final semantics = tester.ensureSemantics();
    try {
      expect(
        tester.getSemantics(notifications),
        isSemantics(
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(tracking);
      await tester.pumpAndSettle();
      expect(find.text('Consider topics new'), findsOneWidget);
      expect(
        tester.getSemantics(tracking),
        isSemantics(
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('editing enables save and sends only the changed flat field', (
    tester,
  ) async {
    final writeGate = Completer<void>();
    final fixture = await _fixture(writeGate: writeGate);
    final semantics = tester.ensureSemantics();
    try {
      await _pumpPage(tester, fixture);
      expect(
        _saveButton(tester, PreferenceSection.notifications).onPressed,
        isNull,
      );

      await tester.tap(find.text('First time and daily'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Never').last);
      await tester.pumpAndSettle();

      expect(
        _saveButton(tester, PreferenceSection.notifications).onPressed,
        isNotNull,
      );
      await tester.tap(_save(PreferenceSection.notifications));
      await tester.pump();
      await tester.pump();

      expect(fixture.api.userPreferenceUpdates, hasLength(1));
      expect(fixture.api.userPreferenceUpdates.single.values, {
        'like_notification_frequency': 3,
      });
      final saving = find.bySemanticsLabel('Saving preferences…');
      expect(saving, findsOneWidget);
      expect(
        tester.getSemantics(saving),
        isSemantics(label: 'Saving preferences…', isLiveRegion: true),
      );
      expect(
        _saveButton(tester, PreferenceSection.notifications).loading,
        isTrue,
      );

      writeGate.complete();
      await tester.pumpAndSettle();

      final saved = find.bySemanticsLabel('Notifications preferences saved.');
      expect(saved, findsOneWidget);
      expect(
        tester.getSemantics(saved),
        isSemantics(
          label: 'Notifications preferences saved.',
          isLiveRegion: true,
        ),
      );
      expect(
        _saveButton(tester, PreferenceSection.notifications).onPressed,
        isNull,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('invalid IANA timezone blocks the write locally', (tester) async {
    final fixture = await _fixture();
    await _pumpPage(tester, fixture);
    await _chooseNarrowSection(tester, PreferenceSection.datesAndReminders);

    await tester.enterText(
      find.byKey(const ValueKey('preferences-timezone')),
      'Mars/Olympus',
    );
    await tester.pump();

    expect(
      find.text('Use a valid IANA timezone, such as Europe/Paris.'),
      findsOneWidget,
    );
    expect(
      _saveButton(tester, PreferenceSection.datesAndReminders).onPressed,
      isNull,
    );
    expect(fixture.api.userPreferenceUpdates, isEmpty);
  });

  testWidgets('server validation error is announced and retains the draft', (
    tester,
  ) async {
    final fixture = await _fixture(
      writeFailure: const WriteException(
        WriteFailure.validation,
        errors: ['The forum rejected this preference.'],
      ),
    );
    final semantics = tester.ensureSemantics();
    try {
      await _pumpPage(tester, fixture);
      await tester.tap(find.byKey(const ValueKey('notify-on-linked-posts')));
      await tester.pump();
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('notify-on-linked-posts')),
            )
            .value,
        isFalse,
      );

      await tester.tap(_save(PreferenceSection.notifications));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('The forum rejected this preference.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('notify-on-linked-posts')),
            )
            .value,
        isFalse,
      );
      expect(
        _saveButton(tester, PreferenceSection.notifications).onPressed,
        isNotNull,
      );
      expect(fixture.shell.instanceFor(_siteUrl)!.user!.timezone, 'Etc/UTC');
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('loading state is a polite live-region announcement', (
    tester,
  ) async {
    final loadGate = Completer<void>();
    final fixture = await _fixture(loadGate: loadGate);
    final semantics = tester.ensureSemantics();
    try {
      await _pumpPage(tester, fixture, settle: false);

      final loading = find.bySemanticsLabel(
        'Loading preferences from preferences.example.',
      );
      expect(loading, findsOneWidget);
      expect(
        tester.getSemantics(loading),
        isSemantics(
          label: 'Loading preferences from preferences.example.',
          isLiveRegion: true,
        ),
      );

      loadGate.complete();
      await tester.pumpAndSettle();
      expect(loading, findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('capabilities hide tracking and disable every editable control', (
    tester,
  ) async {
    final fixture = await _fixture(
      preferences: _preferences.copyWith(
        canEdit: false,
        canChangeTrackingPreferences: false,
      ),
    );
    await _pumpPage(tester, fixture, width: 1000);

    expect(
      find.byKey(const ValueKey('preferences-section-tracking')),
      findsNothing,
    );
    expect(find.text('Tracking'), findsNothing);
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('notify-on-linked-posts')),
          )
          .onChanged,
      isNull,
    );
    expect(
      _saveButton(tester, PreferenceSection.notifications).onPressed,
      isNull,
    );
  });

  testWidgets('web-only settings are disclosed as noninteractive information', (
    tester,
  ) async {
    final fixture = await _fixture();
    final semantics = tester.ensureSemantics();
    try {
      await _pumpPage(tester, fixture);
      final disclosure = find.bySemanticsLabel(
        RegExp(r'^Available on the web\. Account, login, security'),
      );
      expect(disclosure, findsOneWidget);
      expect(find.text('Preferences added by forum plugins'), findsOneWidget);
      expect(
        tester.getSemantics(disclosure),
        isSemantics(isButton: false, hasTapAction: false),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('confirmed date settings update the account mirror and store', (
    tester,
  ) async {
    final fixture = await _fixture();
    await _pumpPage(tester, fixture);
    await _chooseNarrowSection(tester, PreferenceSection.datesAndReminders);

    await tester.enterText(
      find.byKey(const ValueKey('preferences-timezone')),
      'Europe/London',
    );
    await tester.pump();
    fixture.store.saved.clear();
    await tester.tap(_save(PreferenceSection.datesAndReminders));
    await tester.pumpAndSettle();

    final mirrored = fixture.shell.instanceFor(_siteUrl)!.user!;
    expect(mirrored.timezone, 'Europe/London');
    expect(
      mirrored.bookmarkAutoDeletePreference,
      BookmarkAutoDeletePreference.clearReminder,
    );
    expect(fixture.store.saved, isNotEmpty);
    expect(fixture.store.saved.last.single.user?.timezone, 'Europe/London');
  });

  testWidgets('notification save does not mirror unrelated loaded dates', (
    tester,
  ) async {
    final fixture = await _fixture(
      preferences: _preferences.copyWith(timezone: 'Europe/Paris'),
    );
    await _pumpPage(tester, fixture);

    await tester.tap(find.byKey(const ValueKey('notify-on-linked-posts')));
    await tester.pump();
    fixture.store.saved.clear();
    await tester.tap(_save(PreferenceSection.notifications));
    await tester.pumpAndSettle();

    expect(fixture.shell.instanceFor(_siteUrl)!.user!.timezone, 'Etc/UTC');
    expect(fixture.store.saved, isEmpty);
  });
}

final class _RecordingInstanceStore implements InstanceStore {
  _RecordingInstanceStore(this.instances);

  List<DiscourseInstance> instances;
  final List<List<DiscourseInstance>> saved = [];

  @override
  Future<List<DiscourseInstance>> load() async => List.of(instances);

  @override
  Future<void> save(List<DiscourseInstance> instances) async {
    this.instances = List.of(instances);
    saved.add(List.unmodifiable(instances));
  }
}
