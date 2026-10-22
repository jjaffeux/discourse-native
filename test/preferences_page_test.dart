import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/foundation/timezone_environment.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_preferences.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/header_preferences.dart';
import 'package:discourse_native/src/shell/preferences_page.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
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
  pluginValues: {
    'chat/preferences': ChatUserPreferences(
      separateSidebarMode: ChatSeparateSidebarPreference.fullscreen,
    ),
  },
);

final _chatSite = _site.copyWith(
  user: _site.user!.withPlugins(
    _site.user!.plugins.withValue(
      chatCurrentUserDataKey,
      const ChatCurrentUser(
        hasChatEnabled: true,
        canChat: true,
        canDirectMessage: true,
      ),
    ),
  ),
);

typedef _Fixture = ({
  ShellController shell,
  FakeDiscourseApi api,
  _RecordingInstanceStore store,
});

Future<_Fixture> _fixture({
  DiscourseInstance? site,
  UserPreferences preferences = _preferences,
  Completer<void>? loadGate,
  Completer<void>? writeGate,
  WriteException? writeFailure,
}) async {
  final selectedSite = site ?? _chatSite;
  final api = FakeDiscourseApi(
    user: selectedSite.user,
    userPreferences: preferences,
    userPreferencesGate: loadGate,
    userPreferencesWriteGate: writeGate,
    writeFailure: writeFailure,
  );
  final store = _RecordingInstanceStore([selectedSite]);
  final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
  final shell = ShellController(
    instanceStore: store,
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    ownsApi: false,
    plugins: installedPlugins,
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
  ThemeData? theme,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ContentSettingsScope(
      controller: fixture.shell.appSettings,
      child: ShellScope(
        controller: fixture.shell,
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: Scaffold(
            body: SizedBox(
              width: width,
              height: 900,
              child: const PreferencesPage(siteUrl: _siteUrl),
            ),
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

Finder get _timezoneMenu => find.byKey(const ValueKey('preferences-timezone'));
Finder get _timezoneInput =>
    find.descendant(of: _timezoneMenu, matching: find.byType(EditableText));
Future<void> _section(WidgetTester tester, PreferenceSection section) async {
  final tab = find.byKey(ValueKey('preferences-section-${section.keyName}'));
  await tester.ensureVisible(tab);
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

Future<void> _selectNeverLikeNotifications(WidgetTester tester) async {
  await _section(tester, PreferenceSection.notifications);
  await tester.tap(find.text('First time and daily'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Never').last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(TimezoneEnvironment.instance.ensureDatabase);
  for (final width in [320.0, 680.0, 1000.0]) {
    testWidgets('section tabs expose every available preference at $width', (
      tester,
    ) async {
      final fixture = await _fixture();
      await _pumpPage(tester, fixture, width: width);
      expect(find.text('Preferences'), findsOneWidget);
      expect(find.byType(DTabs<PreferenceSection>), findsOneWidget);
      expect(find.byKey(const ValueKey('preferences-save')), findsNothing);
      expect(
        find.byKey(const ValueKey('preferences-timezone')),
        findsOneWidget,
      );
      expect(find.text('Automatically delete bookmarks'), findsNothing);
      for (final section in [
        ...PreferenceSection.values,
        chatPreferenceSection,
      ]) {
        await _section(tester, section);
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets('selects persist immediately and only send the changed field', (
    tester,
  ) async {
    final fixture = await _fixture();
    await _pumpPage(tester, fixture);
    await _selectNeverLikeNotifications(tester);
    expect(fixture.api.userPreferenceUpdates.single.values, {
      'like_notification_frequency': 3,
    });
    expect(
      fixture.shell.instanceFor(_siteUrl)!.user!.likesNotificationsDisabled,
      isTrue,
    );
    expect(
      fixture.store.saved.single.single.user!.likesNotificationsDisabled,
      isTrue,
    );
    expect(
      fixture.shell.preferences
          .stateFor(_siteUrl)!
          .dirty(PreferenceSection.notifications),
      isFalse,
    );
    expect(find.byKey(const ValueKey('preferences-save')), findsNothing);
  });
  testWidgets('plugin preferences keep their real actions within their tab', (
    tester,
  ) async {
    final fixture = await _fixture();
    await _pumpPage(tester, fixture);
    await _section(tester, chatPreferenceSection);
    await tester.ensureVisible(
      find.byType(DSelect<ChatSeparateSidebarPreference>),
    );
    await tester.tap(find.text('When chat is in fullscreen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Always').last);
    await tester.pumpAndSettle();
    expect(fixture.api.userPreferenceUpdates.single.values, {
      'chat_separate_sidebar_mode': 'always',
    });
  });
  testWidgets('quick reversal is saved after the pending first choice', (
    tester,
  ) async {
    final gate = Completer<void>();
    final fixture = await _fixture(writeGate: gate);
    await _pumpPage(tester, fixture);
    await _section(tester, PreferenceSection.notifications);
    final toggle = find.byKey(const ValueKey('notify-on-linked-posts'));
    await tester.tap(toggle);
    await tester.pump();
    expect(fixture.api.userPreferenceUpdates, hasLength(1));
    await tester.tap(toggle);
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(fixture.api.userPreferenceUpdates.map((update) => update.values), [
      {'notify_on_linked_posts': false},
      {'notify_on_linked_posts': true},
    ]);
    expect(
      fixture.shell.preferences
          .stateFor(_siteUrl)!
          .confirmed!
          .notifyOnLinkedPosts,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('timezone filters reject free text and persist a selected zone', (
    tester,
  ) async {
    final fixture = await _fixture();
    await _pumpPage(tester, fixture);
    final entries = tester.widget<DCombobox<String>>(_timezoneMenu).options;
    await tester.enterText(_timezoneInput, 'Mars/Olympus');
    await tester.pumpAndSettle();
    expect(fixture.api.userPreferenceUpdates, isEmpty);
    expect(
      fixture.shell.preferences.stateFor(_siteUrl)!.draft!.timezone,
      'Etc/UTC',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(_timezoneInput).controller.text,
      'Etc/UTC',
    );
    await tester.enterText(_timezoneInput, 'Europe/Lond');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Europe/London').last);
    await tester.pumpAndSettle();
    expect(fixture.api.userPreferenceUpdates.single.values, {
      'timezone': 'Europe/London',
    });
    expect(
      fixture.shell.instanceFor(_siteUrl)!.user!.timezone,
      'Europe/London',
    );
    expect(
      identical(
        tester.widget<DCombobox<String>>(_timezoneMenu).options,
        entries,
      ),
      isTrue,
    );
  });
  testWidgets('failed immediate save retains the draft and offers retry', (
    tester,
  ) async {
    final fixture = await _fixture(
      writeFailure: const WriteException(
        WriteFailure.validation,
        errors: ['The forum rejected this preference.'],
      ),
    );
    final semantics = tester.ensureSemantics();
    await _pumpPage(tester, fixture);
    await _section(tester, PreferenceSection.notifications);
    await tester.tap(find.byKey(const ValueKey('notify-on-linked-posts')));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('The forum rejected this preference.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<DSwitchTile>(
            find.byKey(const ValueKey('notify-on-linked-posts')),
          )
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<DButton>(find.byKey(const ValueKey('preferences-save')))
          .onPressed,
      isNotNull,
    );
    expect(
      fixture.shell.preferences
          .stateFor(_siteUrl)!
          .confirmed!
          .notifyOnLinkedPosts,
      isTrue,
    );
    semantics.dispose();
  });
  testWidgets('denied capabilities hide tracking and prevent edits', (
    tester,
  ) async {
    final fixture = await _fixture(
      preferences: _preferences.copyWith(
        canEdit: false,
        canChangeTrackingPreferences: false,
      ),
    );
    await _pumpPage(tester, fixture);
    expect(
      find.byKey(const ValueKey('preferences-section-tracking')),
      findsNothing,
    );
    expect(tester.widget<DCombobox<String>>(_timezoneMenu).enabled, isFalse);
    await _section(tester, PreferenceSection.notifications);
    expect(
      tester
          .widget<DSwitchTile>(
            find.byKey(const ValueKey('notify-on-linked-posts')),
          )
          .onChanged,
      isNull,
    );
    expect(fixture.api.userPreferenceUpdates, isEmpty);
  });
  testWidgets(
    'notification changes do not mirror unrelated loaded profile data',
    (tester) async {
      final fixture = await _fixture(
        preferences: _preferences.copyWith(timezone: 'Europe/Paris'),
      );
      await _pumpPage(tester, fixture);
      fixture.store.saved.clear();
      await _section(tester, PreferenceSection.notifications);
      await tester.tap(find.byKey(const ValueKey('notify-on-linked-posts')));
      await tester.pumpAndSettle();
      expect(fixture.shell.instanceFor(_siteUrl)!.user!.timezone, 'Etc/UTC');
      expect(fixture.store.saved, isEmpty);
    },
  );
  testWidgets(
    'shows the inherited site chat mode without dirtying the preference',
    (tester) async {
      final site = _chatSite.copyWith(
        config: _site.config.withPlugins(
          _site.config.plugins.withValue(
            chatSettingsDataKey,
            const ChatSettings(
              separateSidebarMode: ChatSeparateSidebarMode.always,
            ),
          ),
        ),
      );
      final fixture = await _fixture(
        site: site,
        preferences: _preferences.withChatPreferences(
          separateSidebarMode: ChatSeparateSidebarPreference.siteDefault,
        ),
      );
      await _pumpPage(tester, fixture);
      await _section(tester, chatPreferenceSection);

      expect(find.text('Always'), findsOneWidget);
      expect(
        fixture.shell.preferences
            .stateFor(_siteUrl)!
            .draft!
            .chatPreferences
            .separateSidebarMode,
        ChatSeparateSidebarPreference.siteDefault,
      );
      expect(
        fixture.shell.preferences
            .stateFor(_siteUrl)!
            .dirty(chatPreferenceSection),
        isFalse,
      );
      expect(fixture.api.userPreferenceUpdates, isEmpty);
    },
  );
  for (final width in [320.0, 1000.0]) {
    for (final brightness in Brightness.values) {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
        testWidgets('preferences load as an accessible skeleton at $width '
            '${brightness.name} ${platform.name}', (tester) async {
          final loadGate = Completer<void>();
          final fixture = await _fixture(loadGate: loadGate);
          final semantics = tester.ensureSemantics();
          try {
            await _pumpPage(
              tester,
              fixture,
              width: width,
              settle: false,
              theme:
                  (brightness == Brightness.dark
                          ? AppTheme.dark
                          : AppTheme.light)
                      .copyWith(platform: platform),
            );

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
            expect(find.text('Loading preferences…'), findsNothing);
            expect(find.byType(DSpinner), findsNothing);
            expect(find.byType(DSkeletonRegion), findsOneWidget);
            expect(find.byType(DSkeleton), findsWidgets);
            expect(find.text('Preferences'), findsOneWidget);
            expect(_timezoneMenu, findsNothing);
            expect(tester.takeException(), isNull);

            loadGate.complete();
            await tester.pumpAndSettle();
            expect(loading, findsNothing);
            expect(find.byType(DSkeletonRegion), findsNothing);
            expect(find.byType(DSkeleton), findsNothing);
            expect(_timezoneMenu, findsOneWidget);
            expect(tester.takeException(), isNull);
          } finally {
            try {
              if (!loadGate.isCompleted) {
                loadGate.complete();
                await tester.pumpAndSettle();
              }
            } finally {
              semantics.dispose();
            }
          }
        });
      }
    }
  }

  testWidgets('a failed preference load replaces the skeleton with retry', (
    tester,
  ) async {
    final loadGate = Completer<void>();
    final fixture = await _fixture(loadGate: loadGate);
    await _pumpPage(tester, fixture, settle: false);
    expect(find.byType(DSkeletonRegion), findsOneWidget);

    loadGate.completeError(StateError('Preferences request failed'));
    await tester.pumpAndSettle();

    expect(find.byType(DSkeletonRegion), findsNothing);
    expect(find.byType(DSkeleton), findsNothing);
    expect(
      find.text("Couldn't load preferences from preferences.example."),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('preferences-retry')), findsOneWidget);
    expect(_timezoneMenu, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('allows an admin to edit Chat when can_chat is false', (
    tester,
  ) async {
    const adminSite = DiscourseInstance(
      url: _siteUrl,
      title: 'Preferences Forum',
      user: DiscourseUser(
        id: 7,
        username: 'reader',
        admin: true,
        timezone: 'Etc/UTC',
      ),
    );
    final fixture = await _fixture(site: adminSite);
    await _pumpPage(tester, fixture, width: 1000);

    final chat = find.byKey(
      const ValueKey('preferences-section-chat/preferences'),
    );
    expect(chat, findsOneWidget);
    await tester.tap(chat);
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byType(DSelect<ChatSeparateSidebarPreference>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('When chat is in fullscreen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Always').last);
    await tester.pumpAndSettle();
    expect(
      fixture.shell.preferences
          .stateFor(_siteUrl)!
          .draft!
          .chatPreferences
          .separateSidebarMode,
      ChatSeparateSidebarPreference.always,
    );
    await tester.pumpAndSettle();

    expect(fixture.api.userPreferenceUpdates.single.values, {
      'chat_separate_sidebar_mode': 'always',
    });
  });
  testWidgets('hides Chat when the site setting disables it', (tester) async {
    final site = _chatSite.copyWith(
      config: _chatSite.config.withPlugins(
        _chatSite.config.plugins.withValue(
          chatSettingsDataKey,
          const ChatSettings(chatEnabled: false),
        ),
      ),
    );
    final fixture = await _fixture(site: site);
    await _pumpPage(tester, fixture, width: 1000);

    expect(
      find.byKey(const ValueKey('preferences-section-chat/preferences')),
      findsNothing,
    );
    expect(find.text('Chat'), findsNothing);
  });
  testWidgets(
    'a mounted preferences page reloads a forgotten account generation',
    (tester) async {
      final fixture = await _fixture();
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.notifications);
      final page = tester.element(find.byType(PreferencesPage));
      expect(fixture.shell.preferences.stateFor(_siteUrl)?.loaded, isTrue);

      fixture.shell.lifecycle.invalidate(_siteUrl);
      fixture.shell.preferences.forget(_siteUrl);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(tester.element(find.byType(PreferencesPage)), same(page));
      expect(fixture.shell.preferences.stateFor(_siteUrl)?.loaded, isTrue);
      expect(find.byType(DSpinner), findsNothing);
      expect(
        find.byKey(const ValueKey('notify-on-linked-posts')),
        findsOneWidget,
      );
    },
  );
  testWidgets('persist confirmed profile settings to the account mirror', (
    tester,
  ) async {
    final fixture = await _fixture();
    await _pumpPage(tester, fixture);
    await _section(tester, PreferenceSection.profile);

    await tester.enterText(_timezoneInput, 'Europe/Lond');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Europe/London'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    final mirrored = fixture.shell.instanceFor(_siteUrl)!.user!;
    expect(mirrored.timezone, 'Europe/London');
    expect(
      mirrored.bookmarkAutoDeletePreference,
      BookmarkAutoDeletePreference.clearReminder,
    );
    expect(fixture.store.saved, hasLength(1));
    expect(fixture.store.saved.last.single.user?.timezone, 'Europe/London');
  });
  testWidgets(
    'persist the confirmed chat mode while preserving chat user state',
    (tester) async {
      const heldChatUser = ChatCurrentUser(
        hasChatEnabled: true,
        canChat: true,
        canDirectMessage: false,
        headerIndicatorPreference: ChatHeaderIndicatorPreference.onlyMentions,
        separateSidebarMode: ChatSeparateSidebarMode.fullscreen,
        lastChannelId: 42,
        ignoredUsernames: ['muted-user'],
      );
      final site = _site.copyWith(
        user: _site.user!.withPlugins(
          _site.user!.plugins.withValue(chatCurrentUserDataKey, heldChatUser),
        ),
      );
      final fixture = await _fixture(site: site);
      await _pumpPage(tester, fixture);
      await _section(tester, chatPreferenceSection);

      await tester.tap(find.text('When chat is in fullscreen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Always'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      const expected = ChatCurrentUser(
        hasChatEnabled: true,
        canChat: true,
        canDirectMessage: false,
        headerIndicatorPreference: ChatHeaderIndicatorPreference.onlyMentions,
        separateSidebarMode: ChatSeparateSidebarMode.always,
        lastChannelId: 42,
        ignoredUsernames: ['muted-user'],
      );
      expect(
        fixture.shell.instanceFor(_siteUrl)!.user!.chatCurrentUser,
        expected,
      );
      expect(fixture.store.saved, hasLength(1));
      expect(fixture.store.saved.single.single.user!.chatCurrentUser, expected);
    },
  );

  testWidgets('non-admin without can_chat has no Chat preference section', (
    tester,
  ) async {
    final fixture = await _fixture(site: _site);
    await _pumpPage(tester, fixture);
    expect(
      find.byKey(const ValueKey('preferences-section-chat/preferences')),
      findsNothing,
    );
  });
  testWidgets(
    'announces automatic saving and confirmed success in live regions',
    (tester) async {
      final gate = Completer<void>();
      final fixture = await _fixture(writeGate: gate);
      final semantics = tester.ensureSemantics();
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.notifications);
      await tester.tap(find.byKey(const ValueKey('notify-on-linked-posts')));
      await tester.pump();
      expect(find.bySemanticsLabel('Saving preferences'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Notifications preferences saved.'),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );
  testWidgets('server bookmark preference still mirrors after confirmation', (
    tester,
  ) async {
    final fixture = await _fixture();
    await _pumpPage(tester, fixture);
    await _section(tester, PreferenceSection.interface);
    expect(find.byType(HeaderTuningPreferences), findsOneWidget);
    await tester.tap(find.text('When the reminder is cleared'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Never').last);
    await tester.pumpAndSettle();
    expect(
      fixture.shell.instanceFor(_siteUrl)!.user!.bookmarkAutoDeletePreference,
      BookmarkAutoDeletePreference.never,
    );
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
