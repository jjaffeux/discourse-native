import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/foundation/timezone_environment.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/preferences_page.dart';
import 'package:discourse_native/src/shell/select.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  chatSeparateSidebarMode: ChatSeparateSidebarPreference.fullscreen,
  canEdit: true,
  canChangeTrackingPreferences: true,
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
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ContentAlignmentScope(
      controller: fixture.shell.appSettings,
      child: ShellScope(
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

Finder get _timezoneMenu => find.byKey(const ValueKey('preferences-timezone'));

Finder get _timezoneInput =>
    find.descendant(of: _timezoneMenu, matching: find.byType(EditableText));

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

Future<void> _selectNeverLikeNotifications(WidgetTester tester) async {
  await tester.tap(find.text('First time and daily'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Never').last);
  await tester.pumpAndSettle();
}

String _sectionLabel(PreferenceSection section) => switch (section) {
  PreferenceSection.profile => 'Profile',
  PreferenceSection.notifications => 'Notifications',
  PreferenceSection.tracking => 'Tracking',
  PreferenceSection.interface => 'Interface',
  PreferenceSection.chat => 'Chat',
};

void main() {
  setUpAll(TimezoneEnvironment.instance.ensureDatabase);

  group('section navigation', () {
    testWidgets('compact form follows physical desktop alignment', (
      tester,
    ) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final fixture = await _fixture();
        await _pumpPage(tester, fixture, width: 740);
        final form = find.byKey(
          const ValueKey((
            'preferences-section',
            PreferenceSection.notifications,
          )),
        );

        expect(tester.getSize(form).width, 680);
        expect(tester.getTopLeft(form).dx, 30);

        await fixture.shell.appSettings.setContentAlignment(
          ContentAlignment.left,
        );
        await tester.pump();
        expect(tester.getTopLeft(form).dx, 16);

        await fixture.shell.appSettings.setContentAlignment(
          ContentAlignment.right,
        );
        await tester.pump();
        expect(tester.getTopLeft(form).dx, 44);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    });

    testWidgets('adapts the picker between narrow and wide layouts', (
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
      expect(find.text('Preferences'), findsNothing);
      final notifications = find.byKey(
        const ValueKey('preferences-section-notifications'),
      );
      final tracking = find.byKey(
        const ValueKey('preferences-section-tracking'),
      );
      expect(notifications, findsOneWidget);
      expect(tracking, findsOneWidget);
      expect(tester.getSize(notifications).height, greaterThanOrEqualTo(48));
      expect(
        tester.widget<InkWell>(notifications).mouseCursor,
        SystemMouseCursors.click,
      );

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

    testWidgets('separates timezone and bookmark cleanup controls', (
      tester,
    ) async {
      final fixture = await _fixture();
      await _pumpPage(tester, fixture, width: 1000);

      final profile = find.byKey(const ValueKey('preferences-section-profile'));
      final interface = find.byKey(
        const ValueKey('preferences-section-interface'),
      );
      expect(profile, findsOneWidget);
      expect(interface, findsOneWidget);
      expect(find.text('Dates & reminders'), findsNothing);

      await tester.tap(profile);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('preferences-timezone')),
        findsOneWidget,
      );
      expect(find.text('Automatically delete bookmarks'), findsNothing);

      await tester.tap(interface);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('preferences-timezone')), findsNothing);
      expect(find.text('Automatically delete bookmarks'), findsOneWidget);
    });

    testWidgets('omits duplicate titles and descriptions from content', (
      tester,
    ) async {
      final fixture = await _fixture();
      await _pumpPage(tester, fixture, width: 1000);

      const descriptions = {
        PreferenceSection.profile:
            'Set the account timezone used for dates and reminders.',
        PreferenceSection.notifications:
            'Choose which forum activity should notify this account.',
        PreferenceSection.tracking:
            'Choose when topics become new, tracked, or watched.',
        PreferenceSection.interface:
            'Choose the default bookmark cleanup behavior.',
        PreferenceSection.chat:
            'Choose whether forum and chat use separate sidebar modes.',
      };

      for (final section in PreferenceSection.values) {
        await tester.tap(
          find.byKey(ValueKey('preferences-section-${section.name}')),
        );
        await tester.pumpAndSettle();

        expect(find.text(_sectionLabel(section)), findsOneWidget);
        expect(find.text(descriptions[section]!), findsNothing);
      }
    });
  });

  group('preference editing', () {
    testWidgets(
      'enables Save only for edits and sends the changed flat field',
      (tester) async {
        final fixture = await _fixture();
        await _pumpPage(tester, fixture);

        expect(
          _saveButton(tester, PreferenceSection.notifications).onPressed,
          isNull,
        );

        await _selectNeverLikeNotifications(tester);

        expect(
          _saveButton(tester, PreferenceSection.notifications).onPressed,
          isNotNull,
        );
        await tester.tap(_save(PreferenceSection.notifications));
        await tester.pumpAndSettle();

        expect(fixture.api.userPreferenceUpdates, hasLength(1));
        expect(fixture.api.userPreferenceUpdates.single.values, {
          'like_notification_frequency': 3,
        });
        expect(
          _saveButton(tester, PreferenceSection.notifications).onPressed,
          isNull,
        );
      },
    );

    testWidgets(
      'offers the three web chat sidebar choices and saves the wire value',
      (tester) async {
        final fixture = await _fixture();
        await _pumpPage(tester, fixture);
        await _chooseNarrowSection(tester, PreferenceSection.chat);

        expect(
          find.text('Show separate sidebar modes for forum and chat'),
          findsOneWidget,
        );
        expect(find.text('When chat is in fullscreen'), findsOneWidget);
        expect(_saveButton(tester, PreferenceSection.chat).onPressed, isNull);

        await tester.tap(find.text('When chat is in fullscreen'));
        await tester.pumpAndSettle();

        expect(find.text('Always'), findsOneWidget);
        expect(find.text('Never'), findsOneWidget);
        expect(find.text('Default'), findsNothing);

        await tester.tap(find.text('Always'));
        await tester.pumpAndSettle();
        expect(
          _saveButton(tester, PreferenceSection.chat).onPressed,
          isNotNull,
        );

        await tester.tap(_save(PreferenceSection.chat));
        await tester.pumpAndSettle();

        expect(fixture.api.userPreferenceUpdates.single.values, {
          'chat_separate_sidebar_mode': 'always',
        });
        expect(_saveButton(tester, PreferenceSection.chat).onPressed, isNull);
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
          preferences: _preferences.copyWith(
            chatSeparateSidebarMode: ChatSeparateSidebarPreference.siteDefault,
          ),
        );
        await _pumpPage(tester, fixture);
        await _chooseNarrowSection(tester, PreferenceSection.chat);

        expect(find.text('Always'), findsOneWidget);
        expect(
          fixture.shell.preferences
              .stateFor(_siteUrl)!
              .draft!
              .chatSeparateSidebarMode,
          ChatSeparateSidebarPreference.siteDefault,
        );
        expect(
          fixture.shell.preferences
              .stateFor(_siteUrl)!
              .dirty(PreferenceSection.chat),
          isFalse,
        );
        expect(_saveButton(tester, PreferenceSection.chat).onPressed, isNull);
        expect(fixture.api.userPreferenceUpdates, isEmpty);
      },
    );

    testWidgets('announces pending and completed saves without shrinking', (
      tester,
    ) async {
      final writeGate = Completer<void>();
      final fixture = await _fixture(writeGate: writeGate);
      final semantics = tester.ensureSemantics();
      try {
        await _pumpPage(tester, fixture);
        await _selectNeverLikeNotifications(tester);
        final idleButtonSize = tester.getSize(
          _save(PreferenceSection.notifications),
        );
        await tester.tap(_save(PreferenceSection.notifications));
        await tester.pump();
        await tester.pump();

        final saving = find.bySemanticsLabel('Saving preferences');
        expect(saving, findsOneWidget);
        expect(
          tester.getSemantics(saving),
          isSemantics(
            label: 'Saving preferences',
            value: 'Loading',
            isButton: true,
            isEnabled: false,
            isLiveRegion: true,
          ),
        );
        expect(find.text('Saving changes…'), findsOneWidget);
        expect(find.text('Saving preferences…'), findsNothing);
        final savingButtonSize = tester.getSize(
          _save(PreferenceSection.notifications),
        );
        expect(savingButtonSize.width, greaterThan(savingButtonSize.height));
        expect(
          savingButtonSize.width,
          greaterThanOrEqualTo(idleButtonSize.width),
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
        try {
          if (!writeGate.isCompleted) {
            writeGate.complete();
            await tester.pumpAndSettle();
          }
        } finally {
          semantics.dispose();
        }
      }
    });

    testWidgets('filters known timezones without accepting free text', (
      tester,
    ) async {
      final fixture = await _fixture();
      await _pumpPage(tester, fixture);
      await _chooseNarrowSection(tester, PreferenceSection.profile);

      final menu = tester.widget<DropdownMenu<String>>(_timezoneMenu);
      expect(menu.enableFilter, isTrue);
      expect(menu.enableSearch, isTrue);
      expect(
        menu.dropdownMenuEntries.map((entry) => entry.value),
        contains('Europe/London'),
      );

      await tester.enterText(_timezoneInput, 'Mars/Olympus');
      await tester.pump();

      expect(find.text('Europe/London'), findsNothing);
      expect(
        fixture.shell.preferences.stateFor(_siteUrl)!.draft!.timezone,
        'Etc/UTC',
      );
      expect(_saveButton(tester, PreferenceSection.profile).onPressed, isNull);
      expect(fixture.api.userPreferenceUpdates, isEmpty);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        tester.widget<EditableText>(_timezoneInput).controller.text,
        'Etc/UTC',
      );

      await tester.enterText(_timezoneInput, 'Europe/Lond');
      await tester.pump();
      expect(find.text('Europe/London'), findsOneWidget);

      await tester.tap(find.text('Europe/London'));
      await tester.pumpAndSettle();

      expect(
        fixture.shell.preferences.stateFor(_siteUrl)!.draft!.timezone,
        'Europe/London',
      );
      expect(
        _saveButton(tester, PreferenceSection.profile).onPressed,
        isNotNull,
      );
    });

    testWidgets('announces server validation errors and retains the draft', (
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
  });

  group('loading and capabilities', () {
    testWidgets('announces loading in a polite live region', (tester) async {
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

    testWidgets('hide tracking and disable editing when denied', (
      tester,
    ) async {
      final fixture = await _fixture(
        site: _site,
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
        find.byKey(const ValueKey('preferences-section-chat')),
        findsNothing,
      );
      expect(find.text('Chat'), findsNothing);
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

      final chat = find.byKey(const ValueKey('preferences-section-chat'));
      expect(chat, findsOneWidget);
      await tester.tap(chat);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<DropdownButtonFormField<ChatSeparateSidebarPreference>>(
              find.byType(
                DropdownButtonFormField<ChatSeparateSidebarPreference>,
              ),
            )
            .onChanged,
        isNotNull,
      );
      await tester.tap(find.text('When chat is in fullscreen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Always'));
      await tester.pumpAndSettle();
      await tester.tap(_save(PreferenceSection.chat));
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
        find.byKey(const ValueKey('preferences-section-chat')),
        findsNothing,
      );
      expect(find.text('Chat'), findsNothing);
    });
  });

  group('account mirror updates', () {
    testWidgets('persist confirmed profile settings to the account mirror', (
      tester,
    ) async {
      final fixture = await _fixture();
      await _pumpPage(tester, fixture);
      await _chooseNarrowSection(tester, PreferenceSection.profile);

      await tester.enterText(_timezoneInput, 'Europe/Lond');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Europe/London'));
      await tester.pumpAndSettle();
      fixture.store.saved.clear();
      await tester.tap(_save(PreferenceSection.profile));
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

    testWidgets('persist only the confirmed bookmark preference', (
      tester,
    ) async {
      final fixture = await _fixture();
      await _pumpPage(tester, fixture);
      await _chooseNarrowSection(tester, PreferenceSection.interface);

      await tester.tap(find.text('When the reminder is cleared'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Never').last);
      await tester.pumpAndSettle();
      fixture.store.saved.clear();
      await tester.tap(_save(PreferenceSection.interface));
      await tester.pumpAndSettle();

      final mirrored = fixture.shell.instanceFor(_siteUrl)!.user!;
      expect(mirrored.timezone, 'Etc/UTC');
      expect(
        mirrored.bookmarkAutoDeletePreference,
        BookmarkAutoDeletePreference.never,
      );
      expect(fixture.api.userPreferenceUpdates.single.values, {
        'bookmark_auto_delete_preference': 0,
      });
      expect(fixture.store.saved, hasLength(1));
      expect(
        fixture.store.saved.single.single.user?.bookmarkAutoDeletePreference,
        BookmarkAutoDeletePreference.never,
      );
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
        await _chooseNarrowSection(tester, PreferenceSection.chat);

        await tester.tap(find.text('When chat is in fullscreen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Always'));
        await tester.pumpAndSettle();
        await tester.tap(_save(PreferenceSection.chat));
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
        expect(
          fixture.store.saved.single.single.user!.chatCurrentUser,
          expected,
        );
      },
    );

    testWidgets(
      'ignore unrelated loaded profile fields after notification save',
      (tester) async {
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
      },
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
