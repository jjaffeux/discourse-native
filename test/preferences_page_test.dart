import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/foundation/icons/d_icons.dart';
import 'package:discourse_native/src/foundation/icons/d_native_icons.dart';
import 'package:discourse_native/src/foundation/timezone_environment.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/user_auth_token.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/models/user_profile.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_preferences.dart';
import 'package:discourse_native/src/shell/composer/upload_picker.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/header_preferences.dart';
import 'package:discourse_native/src/shell/preference_fields.dart';
import 'package:discourse_native/src/shell/preferences_avatar_row.dart';
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
  FakeDiscourseApi? apiOverride,
  Map<String, List<FoundUser>> userSearches = const {},
}) async {
  var selectedSite = site ?? _chatSite;
  if (!selectedSite.config.plugins.contains(chatSettingsDataKey)) {
    selectedSite = selectedSite.copyWith(
      config: selectedSite.config.withPlugins(
        selectedSite.config.plugins.withValue(
          chatSettingsDataKey,
          const ChatSettings(),
        ),
      ),
    );
  }
  final api =
      apiOverride ??
      FakeDiscourseApi(
        models: bundledPluginCodec,
        user: selectedSite.user,
        userPreferences: preferences,
        userPreferencesGate: loadGate,
        userPreferencesWriteGate: writeGate,
        writeFailure: writeFailure,
        userSearches: userSearches,
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
  Future<ComposerUploadFile?> Function()? pickPicture,
  Future<bool> Function(String url)? openLink,
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
              child: PreferencesPage(
                siteUrl: _siteUrl,
                pickPicture: pickPicture ?? pickProfilePicture,
                openLink: openLink ?? (_) async => false,
              ),
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
Finder get _bio => find.byKey(const ValueKey('preferences-bio'));
Finder get _bioInput =>
    find.descendant(of: _bio, matching: find.byType(EditableText));
Finder get _bioSaveFinder => find.byKey(const ValueKey('preferences-bio-save'));
DButton _bioSave(WidgetTester tester) => tester.widget<DButton>(_bioSaveFinder);
final _pictures = _preferences.copyWith(
  canEditAvatar: true,
  canUploadAvatar: true,
);
Finder get _changePicture =>
    find.byKey(const ValueKey('preferences-avatar-change'));
Finder get _defaultPicture =>
    find.byKey(const ValueKey('preferences-avatar-default'));
Finder get _pictureError =>
    find.byKey(const ValueKey('preferences-avatar-error'));
Future<ComposerUploadFile?> _pickMe() async => ComposerUploadFile(
  name: 'me.png',
  length: () async => 3,
  openRead: () => Stream.value([1, 2, 3]),
);
final _muting = _preferences.copyWith(
  canMuteUsers: true,
  mutedUsernames: ['sam'],
);
const _foundPeople = {
  'ro': [
    FoundUser(username: 'robin', name: 'Robin Hood'),
    FoundUser(username: 'Reader', name: 'The reader'),
    FoundUser(username: 'rory'),
  ],
};
Finder get _mutedUsers => find.byKey(const ValueKey('preferences-muted-users'));
Finder get _mutedSearch =>
    find.descendant(of: _mutedUsers, matching: find.byType(EditableText));
Finder get _mutedSaveFinder =>
    find.byKey(const ValueKey('preferences-muted-users-save'));
DButton _mutedSave(WidgetTester tester) =>
    tester.widget<DButton>(_mutedSaveFinder);
Finder _mutedChip(String username) => find.descendant(
  of: _mutedUsers,
  matching: find.widgetWithText(DComboboxChip<String>, username),
);
final _ignoring = _muting.copyWith(
  canIgnoreUsers: true,
  ignoredUsernames: ['pat'],
);
Finder get _ignorePicker =>
    find.byKey(const ValueKey('preferences-ignore-user'));
Finder get _ignoreSearch =>
    find.descendant(of: _ignorePicker, matching: find.byType(EditableText));
Finder get _ignoreSubmitFinder =>
    find.byKey(const ValueKey('preferences-ignore-submit'));
DButton _ignoreSubmit(WidgetTester tester) =>
    tester.widget<DButton>(_ignoreSubmitFinder);
Finder _ignoredRow(String username) =>
    find.byKey(ValueKey('preferences-ignored-user-$username'));
Finder _stopIgnoring(String username) =>
    find.byKey(ValueKey('preferences-stop-ignoring-$username'));
Finder get _ignoreError =>
    find.byKey(const ValueKey('preferences-ignored-users-error'));

Future<void> _chooseToIgnore(WidgetTester tester, String username) async {
  await _searchPeople(tester, _ignoreSearch, 'ro');
  await tester.tap(find.byKey(ValueKey('ignore-user-$username')));
  await tester.pumpAndSettle();
}

final _withEmail = _preferences.copyWith(
  email: 'reader@example.org',
  unconfirmedEmails: ['pending@example.org'],
  canEditEmail: true,
);
Finder get _newEmail => find.byKey(const ValueKey('preferences-email-new'));
Finder get _newEmailInput =>
    find.descendant(of: _newEmail, matching: find.byType(EditableText));
Finder get _changeEmailFinder =>
    find.byKey(const ValueKey('preferences-email-change'));
DButton _changeEmail(WidgetTester tester) =>
    tester.widget<DButton>(_changeEmailFinder);
Finder get _emailSent => find.byKey(const ValueKey('preferences-email-sent'));
Finder get _emailError => find.byKey(const ValueKey('preferences-email-error'));

final _sessions = _preferences.copyWith(
  authTokens: [
    UserAuthToken(
      id: 41,
      browser: 'Firefox',
      os: 'macOS',
      location: 'Paris, France',
      seenAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
    const UserAuthToken(id: 42, browser: 'Safari', device: 'iPhone'),
  ],
);
Finder _session(int id) => find.byKey(ValueKey('preferences-auth-token-$id'));
Finder _signOut(int id) =>
    find.byKey(ValueKey('preferences-auth-token-revoke-$id'));
Finder get _confirmSignOut =>
    find.byKey(const ValueKey('preferences-auth-token-confirm'));
Finder _openWebsite(String row) =>
    find.byKey(ValueKey('preferences-security-open-$row'));

Future<void> _signOutSession(WidgetTester tester, int id) async {
  await tester.ensureVisible(_signOut(id));
  await tester.tap(_signOut(id));
  await tester.pumpAndSettle();
  await tester.tap(_confirmSignOut);
}

Finder _removeMuted(String username) => find.descendant(
  of: _mutedChip(username),
  matching: find.byWidgetPredicate(
    (widget) => widget is DIcon && widget.icon == DIcons.xmark,
  ),
);

/// The picker's results open over the button below it until dismissed.
Future<void> _saveMuted(WidgetTester tester) async {
  await tester.tapAt(const Offset(4, 4));
  await tester.pumpAndSettle();
  await tester.ensureVisible(_mutedSaveFinder);
  await tester.tap(_mutedSaveFinder);
}

/// Types into a user picker and waits out its typing pause.
Future<void> _searchPeople(
  WidgetTester tester,
  Finder input,
  String term,
) async {
  await tester.ensureVisible(input);
  await tester.tap(input);
  await tester.enterText(input, term);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

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

Finder get _titleMark => find.descendant(
  of: find
      .ancestor(of: find.text('Preferences'), matching: find.byType(Row))
      .first,
  matching: find.byWidgetPredicate(
    (widget) => widget is DIcon && widget.icon == DNativeIcons.sliders,
  ),
);

void main() {
  setUpAll(TimezoneEnvironment.instance.ensureDatabase);
  for (final width in [320.0, 680.0, 1000.0]) {
    testWidgets('section tabs expose every available preference at $width', (
      tester,
    ) async {
      final fixture = await _fixture();
      await _pumpPage(tester, fixture, width: width);
      expect(find.text('Preferences'), findsOneWidget);
      expect(_titleMark, findsOneWidget);
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
  group('about me', () {
    testWidgets('shows the loaded bio and saves only when asked', (
      tester,
    ) async {
      final fixture = await _fixture(
        preferences: _preferences.copyWith(bioRaw: 'I like boats.'),
      );
      await _pumpPage(tester, fixture);
      expect(
        tester.widget<EditableText>(_bioInput).controller.text,
        'I like boats.',
      );
      expect(_bioSave(tester).onPressed, isNull);

      await tester.enterText(_bioInput, 'I like trains.');
      await tester.pumpAndSettle();
      final typed = fixture.shell.preferences.stateFor(_siteUrl)!;
      expect(typed.dirty(PreferenceSection.about), isTrue);
      expect(fixture.api.userPreferenceUpdates, isEmpty);
      expect(find.byKey(const ValueKey('preferences-save')), findsNothing);

      await tester.ensureVisible(_bioSaveFinder);
      await tester.tap(_bioSaveFinder);
      await tester.pumpAndSettle();
      expect(fixture.api.userPreferenceUpdates.single.values, {
        'bio_raw': 'I like trains.',
      });
      final saved = fixture.shell.preferences.stateFor(_siteUrl)!;
      expect(saved.dirty(PreferenceSection.about), isFalse);
      expect(saved.confirmed!.bioRaw, 'I like trains.');
      expect(_bioSave(tester).onPressed, isNull);
      expect(find.text('About me preferences saved.'), findsOneWidget);
    });

    testWidgets('a timezone choice leaves the typed bio unsent', (
      tester,
    ) async {
      final fixture = await _fixture();
      await _pumpPage(tester, fixture);
      await tester.enterText(_bioInput, 'Half a thou');
      await tester.pumpAndSettle();
      await tester.enterText(_timezoneInput, 'Europe/Lond');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Europe/London').last);
      await tester.pumpAndSettle();

      expect(fixture.api.userPreferenceUpdates.single.values, {
        'timezone': 'Europe/London',
      });
      expect(
        tester.widget<EditableText>(_bioInput).controller.text,
        'Half a thou',
      );
      expect(_bioSave(tester).onPressed, isNotNull);
    });

    testWidgets('a refused bio keeps the text and names the reason', (
      tester,
    ) async {
      final fixture = await _fixture(
        writeFailure: const WriteException(
          WriteFailure.validation,
          errors: ['About Me is too long (maximum is 3000 characters)'],
        ),
      );
      await _pumpPage(tester, fixture);
      await tester.enterText(_bioInput, 'Far too long');
      await tester.pumpAndSettle();
      await tester.ensureVisible(_bioSaveFinder);
      await tester.tap(_bioSaveFinder);
      await tester.pumpAndSettle();

      expect(
        find.text('About Me is too long (maximum is 3000 characters)'),
        findsOneWidget,
      );
      expect(
        tester.widget<EditableText>(_bioInput).controller.text,
        'Far too long',
      );
      expect(_bioSave(tester).onPressed, isNotNull);
      expect(find.byKey(const ValueKey('preferences-save')), findsNothing);
    });

    testWidgets('the field follows a bio that changed underneath it', (
      tester,
    ) async {
      final fixture = await _fixture(
        preferences: _preferences.copyWith(bioRaw: 'Before'),
      );
      await _pumpPage(tester, fixture);
      fixture.api.userPreferences = _preferences.copyWith(bioRaw: 'Elsewhere');
      await fixture.shell.preferences.load(
        fixture.shell.instanceFor(_siteUrl)!,
        refresh: true,
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<EditableText>(_bioInput).controller.text,
        'Elsewhere',
      );
      expect(_bioSave(tester).onPressed, isNull);
    });

    testWidgets('a bio the site owns is read-only and says why', (
      tester,
    ) async {
      final fixture = await _fixture(
        preferences: _preferences.copyWith(
          bioRaw: 'From the directory',
          canChangeBio: false,
        ),
      );
      await _pumpPage(tester, fixture);

      expect(tester.widget<DTextarea>(_bio).enabled, isFalse);
      expect(_bioSave(tester).onPressed, isNull);
      expect(
        find.text('This site sets About me from its sign-in provider.'),
        findsOneWidget,
      );
    });

    testWidgets('saving refreshes a profile page already showing the reader', (
      tester,
    ) async {
      final fixture = await _fixture();
      final asked = <String>[];
      fixture.api.userProfileHandler = (siteUrl, username) async {
        asked.add(username);
        return UserProfile(card: UserCard(id: 7, username: username));
      };
      await _pumpPage(tester, fixture);
      await tester.enterText(_bioInput, 'Unopened');
      await tester.pumpAndSettle();
      await tester.ensureVisible(_bioSaveFinder);
      await tester.tap(_bioSaveFinder);
      await tester.pumpAndSettle();
      expect(asked, isEmpty);

      await fixture.shell.userProfile.load(
        fixture.shell.instanceFor(_siteUrl)!,
        'reader',
      );
      await tester.enterText(_bioInput, 'Opened');
      await tester.pumpAndSettle();
      await tester.tap(_bioSaveFinder);
      await tester.pumpAndSettle();
      expect(asked, ['reader', 'reader']);
    });

    testWidgets('a typed bio survives a refresh that brings other changes', (
      tester,
    ) async {
      final fixture = await _fixture(
        preferences: _preferences.copyWith(bioRaw: 'I like boats.'),
      );
      await _pumpPage(tester, fixture);
      await tester.enterText(_bioInput, 'Still typing');
      await tester.pumpAndSettle();

      fixture.api.userPreferences = _preferences.copyWith(
        bioRaw: 'Edited on the web',
        timezone: 'Asia/Tokyo',
      );
      await fixture.shell.preferences.load(
        fixture.shell.instanceFor(_siteUrl)!,
        refresh: true,
      );
      await tester.pumpAndSettle();

      final state = fixture.shell.preferences.stateFor(_siteUrl)!;
      expect(state.confirmed?.bioRaw, 'Edited on the web');
      expect(state.draft?.timezone, 'Asia/Tokyo');
      expect(
        tester.widget<EditableText>(_bioInput).controller.text,
        'Still typing',
      );
      expect(_bioSave(tester).onPressed, isNotNull);

      await tester.ensureVisible(_bioSaveFinder);
      await tester.tap(_bioSaveFinder);
      await tester.pumpAndSettle();
      expect(fixture.api.userPreferenceUpdates.single.values, {
        'bio_raw': 'Still typing',
      });
    });

    testWidgets('the field and its save button are named for a screen reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final fixture = await _fixture();
      await _pumpPage(tester, fixture);
      await tester.enterText(_bioInput, 'Hello');
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(_bioInput),
        isSemantics(
          isTextField: true,
          isMultiline: true,
          label: 'About me',
          value: 'Hello',
        ),
      );
      expect(find.bySemanticsLabel('Save About me'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('fits a phone at twice the text size', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final fixture = await _fixture(
        preferences: _preferences.copyWith(bioRaw: 'I like boats.'),
      );
      await _pumpPage(tester, fixture, width: 320);
      await tester.ensureVisible(_bioSaveFinder);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('About me'), findsOneWidget);
      expect(tester.getSize(_bio).width, lessThanOrEqualTo(320));
    });
  });

  group('muted users', () {
    testWidgets('shows the muted people and saves an added one when asked', (
      tester,
    ) async {
      final fixture = await _fixture(
        preferences: _muting,
        userSearches: _foundPeople,
      );
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.users);
      expect(_mutedChip('sam'), findsOneWidget);
      expect(_mutedSave(tester).onPressed, isNull);

      await _searchPeople(tester, _mutedSearch, 'ro');
      expect(find.text('Robin Hood'), findsOneWidget);
      expect(find.text('@rory'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mute-user-Reader')),
        findsNothing,
        reason: 'the reader cannot mute themselves',
      );
      await tester.tap(find.byKey(const ValueKey('mute-user-robin')));
      await tester.pumpAndSettle();
      expect(_mutedChip('robin'), findsOneWidget);
      expect(fixture.api.userPreferenceUpdates, isEmpty);
      expect(
        fixture.shell.preferences
            .stateFor(_siteUrl)!
            .dirty(PreferenceSection.users),
        isTrue,
      );

      await _saveMuted(tester);
      await tester.pumpAndSettle();
      expect(fixture.api.userPreferenceUpdates.single.values, {
        'muted_usernames': 'robin,sam',
      });
      expect(_mutedSave(tester).onPressed, isNull);
      expect(find.text('Users preferences saved.'), findsOneWidget);
    });

    testWidgets('a chip removes its person from the list to save', (
      tester,
    ) async {
      final fixture = await _fixture(preferences: _muting);
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.users);

      await tester.tap(_removeMuted('sam'));
      await tester.pumpAndSettle();
      expect(_mutedChip('sam'), findsNothing);
      expect(fixture.api.userPreferenceUpdates, isEmpty);

      await _saveMuted(tester);
      await tester.pumpAndSettle();
      expect(fixture.api.userPreferenceUpdates.single.values, {
        'muted_usernames': '',
      });
      expect(
        fixture.shell.preferences.stateFor(_siteUrl)!.confirmed!.mutedUsernames,
        isEmpty,
      );
    });

    testWidgets('an empty list offers the search and nothing to save', (
      tester,
    ) async {
      final fixture = await _fixture(
        preferences: _muting.copyWith(mutedUsernames: const []),
      );
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.users);

      expect(find.byType(DComboboxChip<String>), findsNothing);
      expect(find.text('Add a user'), findsOneWidget);
      expect(_mutedSave(tester).onPressed, isNull);
    });

    testWidgets('the save button waits while the list is on its way', (
      tester,
    ) async {
      final gate = Completer<void>();
      final fixture = await _fixture(preferences: _muting, writeGate: gate);
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.users);
      await tester.tap(_removeMuted('sam'));
      await tester.pumpAndSettle();
      await _saveMuted(tester);
      await tester.pump();
      await tester.pump();

      expect(_mutedSave(tester).loading, isTrue);
      expect(_mutedSave(tester).onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();
      expect(_mutedSave(tester).loading, isFalse);
    });

    testWidgets('a refused list stays as edited and names the reason', (
      tester,
    ) async {
      final fixture = await _fixture(
        preferences: _muting,
        writeFailure: const WriteException(
          WriteFailure.validation,
          errors: ['That list was refused.'],
        ),
      );
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.users);
      await tester.tap(_removeMuted('sam'));
      await tester.pumpAndSettle();
      await _saveMuted(tester);
      await tester.pumpAndSettle();

      expect(find.text('That list was refused.'), findsOneWidget);
      expect(_mutedChip('sam'), findsNothing);
      expect(_mutedSave(tester).onPressed, isNotNull);
      expect(
        fixture.shell.preferences.stateFor(_siteUrl)!.confirmed!.mutedUsernames,
        ['sam'],
      );
    });

    testWidgets('an account that may not mute is told so', (tester) async {
      final fixture = await _fixture(
        preferences: _muting.copyWith(canMuteUsers: false),
      );
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.users);

      expect(_mutedUsers, findsNothing);
      expect(_mutedSaveFinder, findsNothing);
      expect(
        find.text('This site does not let this account mute people yet.'),
        findsOneWidget,
      );
    });

    testWidgets('the list and its save button are named for a screen reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final fixture = await _fixture(preferences: _muting);
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.users);

      expect(find.bySemanticsLabel('Remove sam'), findsOneWidget);
      expect(find.bySemanticsLabel('Save muted users'), findsOneWidget);
      expect(tester.getSemantics(_mutedSearch), isSemantics(isTextField: true));
      semantics.dispose();
    });

    testWidgets('fits a phone at twice the text size', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final fixture = await _fixture(
        preferences: _muting.copyWith(
          mutedUsernames: ['sam', 'a_rather_long_username', 'robin'],
        ),
      );
      await _pumpPage(tester, fixture, width: 320);
      await _section(tester, PreferenceSection.users);
      await tester.ensureVisible(_mutedSaveFinder);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.getSize(_mutedUsers).width, lessThanOrEqualTo(320));
    });
  });

  group('ignored users', () {
    testWidgets('lists the ignored people and stops ignoring one at once', (
      tester,
    ) async {
      final fixture = await _fixture(preferences: _ignoring);
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.users);
      expect(_ignoredRow('pat'), findsOneWidget);
      expect(find.text('@pat'), findsOneWidget);
      expect(_ignoreSubmit(tester).onPressed, isNull);

      await tester.ensureVisible(_stopIgnoring('pat'));
      await tester.tap(_stopIgnoring('pat'));
      await tester.pumpAndSettle();

      expect(fixture.api.ignoreRequests, [(username: 'pat', until: null)]);
      expect(_ignoredRow('pat'), findsNothing);
      expect(find.text('You are not ignoring anyone.'), findsOneWidget);
      expect(fixture.api.userPreferenceUpdates, isEmpty);
      final state = fixture.shell.preferences.stateFor(_siteUrl)!;
      expect(state.confirmed!.ignoredUsernames, isEmpty);
      expect(state.dirty(PreferenceSection.users), isFalse);
    });

    testWidgets('a found person is ignored for the chosen time', (
      tester,
    ) async {
      final fixture = await _fixture(
        preferences: _ignoring.copyWith(mutedUsernames: ['sam', 'robin']),
        userSearches: _foundPeople,
      );
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.users);
      expect(_mutedChip('robin'), findsOneWidget);

      await _searchPeople(tester, _ignoreSearch, 'ro');
      expect(
        find.byKey(const ValueKey('ignore-user-Reader')),
        findsNothing,
        reason: 'the reader cannot ignore themselves',
      );
      await tester.tap(find.byKey(const ValueKey('ignore-user-robin')));
      await tester.pumpAndSettle();
      expect(fixture.api.ignoreRequests, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey('preferences-ignore-duration')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('For one year').last);
      await tester.pumpAndSettle();
      final before = DateTime.now();
      await tester.tap(_ignoreSubmitFinder);
      await tester.pumpAndSettle();

      final request = fixture.api.ignoreRequests.single;
      expect(request.username, 'robin');
      expect(
        request.until!.difference(before).inDays,
        inInclusiveRange(364, 365),
      );
      expect(_ignoredRow('robin'), findsOneWidget);
      expect(_ignoredRow('pat'), findsOneWidget);
      expect(
        _mutedChip('robin'),
        findsNothing,
        reason: 'core lifts the mute of a person it starts ignoring',
      );
      expect(
        fixture.shell.preferences
            .stateFor(_siteUrl)!
            .dirty(PreferenceSection.users),
        isFalse,
      );
      expect(tester.widget<EditableText>(_ignoreSearch).controller.text, '');
      expect(_ignoreSubmit(tester).onPressed, isNull);
    });

    testWidgets('every action waits while a request is on its way', (
      tester,
    ) async {
      final gate = Completer<void>();
      final fixture = await _fixture(preferences: _ignoring);
      fixture.api.ignoreHandler = (_, _) => gate.future;
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.users);

      await tester.tap(_stopIgnoring('pat'));
      await tester.pump();
      await tester.pump();
      final stop = tester.widget<DButton>(_stopIgnoring('pat'));
      expect(stop.loading, isTrue);
      expect(stop.onPressed, isNull);
      expect(_ignoreSubmit(tester).onPressed, isNull);
      expect(_ignoredRow('pat'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(_ignoredRow('pat'), findsNothing);
    });

    testWidgets('a refused ignore says why and changes nothing', (
      tester,
    ) async {
      final fixture = await _fixture(
        preferences: _ignoring,
        userSearches: _foundPeople,
      );
      fixture.api.ignoreHandler = (_, _) async => throw const WriteException(
        WriteFailure.validation,
        errors: ['You cannot ignore that user.'],
      );
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.users);
      await _chooseToIgnore(tester, 'robin');
      await tester.tap(_ignoreSubmitFinder);
      await tester.pumpAndSettle();

      expect(_ignoreError, findsOneWidget);
      expect(find.text('You cannot ignore that user.'), findsOneWidget);
      expect(_ignoredRow('robin'), findsNothing);
      expect(_ignoreSubmit(tester).onPressed, isNotNull);

      fixture.api.ignoreHandler = null;
      await tester.tap(_ignoreSubmitFinder);
      await tester.pumpAndSettle();
      expect(_ignoreError, findsNothing);
      expect(_ignoredRow('robin'), findsOneWidget);
    });

    testWidgets('an account that may not ignore is offered nothing', (
      tester,
    ) async {
      final fixture = await _fixture(
        preferences: _ignoring.copyWith(canIgnoreUsers: false),
      );
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.users);

      expect(find.text('Ignored users'), findsNothing);
      expect(_ignorePicker, findsNothing);
      expect(_ignoredRow('pat'), findsNothing);
      expect(_mutedUsers, findsOneWidget);
    });

    testWidgets('its controls are named for a screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      final fixture = await _fixture(preferences: _ignoring);
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.users);

      expect(find.bySemanticsLabel('Stop ignoring pat'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Ignore for')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Ignore a user')), findsWidgets);
      semantics.dispose();
    });

    testWidgets('fits a phone at twice the text size', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final fixture = await _fixture(
        preferences: _ignoring.copyWith(
          ignoredUsernames: ['pat', 'a_rather_long_username_x'],
        ),
      );
      await _pumpPage(tester, fixture, width: 320);
      await _section(tester, PreferenceSection.users);
      await tester.ensureVisible(_ignoreSubmitFinder);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.getSize(_ignorePicker).width, lessThanOrEqualTo(320));
      expect(
        tester.getRect(_ignoredRow('a_rather_long_username_x')).right,
        lessThanOrEqualTo(320),
      );
    });
  });

  group('email', () {
    testWidgets('shows the addresses and requests a change by mail', (
      tester,
    ) async {
      final fixture = await _fixture(preferences: _withEmail);
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.email);
      expect(find.text('reader@example.org'), findsOneWidget);
      expect(find.text('pending@example.org'), findsOneWidget);
      expect(_changeEmail(tester).onPressed, isNull);
      expect(_emailSent, findsNothing);

      await tester.enterText(_newEmailInput, 'READER@example.org');
      await tester.pumpAndSettle();
      expect(
        _changeEmail(tester).onPressed,
        isNull,
        reason: 'the current address is not a change',
      );

      await tester.enterText(_newEmailInput, ' new@example.org');
      await tester.pumpAndSettle();
      await tester.ensureVisible(_changeEmailFinder);
      await tester.tap(_changeEmailFinder);
      await tester.pumpAndSettle();

      expect(fixture.api.emailChangeRequests, [
        (username: 'reader', email: 'new@example.org'),
      ]);
      expect(_emailSent, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('preferences-email-primary')),
          matching: find.text('reader@example.org'),
        ),
        findsOneWidget,
        reason: 'the site keeps the old address until the link is followed',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('preferences-email-unconfirmed')),
          matching: find.text('new@example.org'),
        ),
        findsOneWidget,
      );
      expect(tester.widget<EditableText>(_newEmailInput).controller.text, '');
      expect(fixture.api.userPreferenceUpdates, isEmpty);
      final state = fixture.shell.preferences.stateFor(_siteUrl)!;
      expect(state.confirmed!.email, 'reader@example.org');

      await tester.enterText(_newEmailInput, 'x');
      await tester.pumpAndSettle();
      expect(_emailSent, findsNothing);
    });

    testWidgets('the field and button wait while a request is on its way', (
      tester,
    ) async {
      final gate = Completer<void>();
      final fixture = await _fixture(preferences: _withEmail);
      fixture.api.emailChangeHandler = (_) => gate.future;
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.email);
      await tester.enterText(_newEmailInput, 'new@example.org');
      await tester.pumpAndSettle();
      await tester.tap(_changeEmailFinder);
      await tester.pump();
      await tester.pump();

      expect(_changeEmail(tester).loading, isTrue);
      expect(_changeEmail(tester).onPressed, isNull);
      expect(tester.widget<DInput>(_newEmail).enabled, isFalse);
      expect(_emailSent, findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(_emailSent, findsOneWidget);
    });

    testWidgets('a refused address keeps the text and names the reason', (
      tester,
    ) async {
      final fixture = await _fixture(preferences: _withEmail);
      fixture.api.emailChangeHandler = (_) async => throw const WriteException(
        WriteFailure.validation,
        errors: ['Email is invalid.'],
      );
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.email);
      await tester.enterText(_newEmailInput, 'nope');
      await tester.pumpAndSettle();
      await tester.tap(_changeEmailFinder);
      await tester.pumpAndSettle();

      expect(_emailError, findsOneWidget);
      expect(find.text('Email is invalid.'), findsOneWidget);
      expect(_emailSent, findsNothing);
      expect(
        tester.widget<EditableText>(_newEmailInput).controller.text,
        'nope',
      );
      expect(
        fixture.shell.preferences
            .stateFor(_siteUrl)!
            .confirmed!
            .unconfirmedEmails,
        ['pending@example.org'],
      );

      await tester.enterText(_newEmailInput, 'nope@example.org');
      await tester.pumpAndSettle();
      expect(_emailError, findsNothing);
    });

    testWidgets(
      'an address the site owns is shown without a way to change it',
      (tester) async {
        final fixture = await _fixture(
          preferences: _withEmail.copyWith(canEditEmail: false),
        );
        await _pumpPage(tester, fixture);
        await _section(tester, PreferenceSection.email);

        expect(find.text('reader@example.org'), findsOneWidget);
        expect(_newEmail, findsNothing);
        expect(_changeEmailFinder, findsNothing);
        expect(
          find.byKey(const ValueKey('preferences-email-managed')),
          findsOneWidget,
        );
      },
    );

    testWidgets('an account with no address to show has no Email tab', (
      tester,
    ) async {
      final fixture = await _fixture();
      await _pumpPage(tester, fixture);

      expect(
        find.byKey(const ValueKey('preferences-section-email')),
        findsNothing,
      );
    });

    testWidgets('the field and its button are named for a screen reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final fixture = await _fixture(preferences: _withEmail);
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.email);
      await tester.enterText(_newEmailInput, 'new@example.org');
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(_newEmailInput),
        isSemantics(
          isTextField: true,
          label: 'New email',
          value: 'new@example.org',
        ),
      );
      expect(find.bySemanticsLabel('Change email'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('fits a phone at twice the text size', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final fixture = await _fixture(
        preferences: _withEmail.copyWith(
          email: 'a.rather.long.address@a-long-domain.example.org',
        ),
      );
      await _pumpPage(tester, fixture, width: 320);
      await _section(tester, PreferenceSection.email);
      await tester.ensureVisible(_changeEmailFinder);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.getSize(_newEmail).width, lessThanOrEqualTo(320));
    });
  });

  group('security', () {
    testWidgets('what needs a browser session opens its own web page', (
      tester,
    ) async {
      final opened = <String>[];
      final fixture = await _fixture(preferences: _sessions);
      await _pumpPage(
        tester,
        fixture,
        openLink: (url) async {
          opened.add(url);
          return true;
        },
      );
      await _section(tester, PreferenceSection.security);

      for (final row in ['password', 'second-factor', 'passkeys']) {
        await tester.ensureVisible(_openWebsite(row));
        await tester.tap(_openWebsite(row));
        await tester.pumpAndSettle();
      }

      expect(opened, [
        '$_siteUrl/u/reader/preferences/security',
        '$_siteUrl/u/reader/preferences/second-factor',
        '$_siteUrl/u/reader/preferences/security',
      ]);
      expect(
        find.byKey(const ValueKey('preferences-security-link-error')),
        findsNothing,
      );
      expect(find.byType(DInput), findsNothing);
      expect(find.byType(DInputOTP), findsNothing);
      expect(fixture.api.authTokenRevocations, isEmpty);
    });

    testWidgets('a browser that would not open is reported', (tester) async {
      final fixture = await _fixture(preferences: _sessions);
      await _pumpPage(tester, fixture, openLink: (_) async => false);
      await _section(tester, PreferenceSection.security);

      await tester.tap(_openWebsite('password'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't open the website."), findsOneWidget);
    });

    testWidgets('lists the browsers and signs one out after confirming', (
      tester,
    ) async {
      final fixture = await _fixture(preferences: _sessions);
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.security);
      expect(find.text('Firefox on macOS'), findsOneWidget);
      expect(find.text('Paris, France · Last seen 3d'), findsOneWidget);
      expect(find.text('Safari on iPhone'), findsOneWidget);

      await tester.ensureVisible(_signOut(41));
      await tester.tap(_signOut(41));
      await tester.pumpAndSettle();
      expect(find.text('Sign out this browser?'), findsOneWidget);
      expect(
        find.text('Firefox on macOS will have to sign in again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fixture.api.authTokenRevocations, isEmpty);
      expect(_session(41), findsOneWidget);

      await _signOutSession(tester, 41);
      await tester.pumpAndSettle();
      expect(fixture.api.authTokenRevocations, [
        (username: 'reader', tokenId: 41),
      ]);
      expect(_session(41), findsNothing);
      expect(_session(42), findsOneWidget);
      expect(fixture.api.userPreferenceUpdates, isEmpty);
      expect(
        fixture.shell.preferences
            .stateFor(_siteUrl)!
            .confirmed!
            .authTokens
            .single
            .id,
        42,
      );
    });

    testWidgets('every sign-out waits while one is on its way', (tester) async {
      final gate = Completer<void>();
      final fixture = await _fixture(preferences: _sessions);
      fixture.api.authTokenRevokeHandler = (_) => gate.future;
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.security);
      await _signOutSession(tester, 41);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.widget<DButton>(_signOut(41)).loading, isTrue);
      expect(tester.widget<DButton>(_signOut(41)).onPressed, isNull);
      expect(tester.widget<DButton>(_signOut(42)).onPressed, isNull);
      expect(_session(41), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(_session(41), findsNothing);
      expect(tester.widget<DButton>(_signOut(42)).onPressed, isNotNull);
    });

    testWidgets('a refused sign-out says why and keeps the browser listed', (
      tester,
    ) async {
      final fixture = await _fixture(preferences: _sessions);
      fixture.api.authTokenRevokeHandler = (_) async =>
          throw const WriteException(
            WriteFailure.validation,
            errors: ['That session could not be signed out.'],
          );
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.security);
      await _signOutSession(tester, 41);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('preferences-auth-tokens-error')),
        findsOneWidget,
      );
      expect(
        find.text('That session could not be signed out.'),
        findsOneWidget,
      );
      expect(_session(41), findsOneWidget);
    });

    testWidgets('no sessions and the requesting session offer no sign-out', (
      tester,
    ) async {
      final empty = await _fixture();
      await _pumpPage(tester, empty);
      await _section(tester, PreferenceSection.security);
      expect(find.text('No browsers are signed in.'), findsOneWidget);
      expect(_openWebsite('password'), findsOneWidget);

      final active = await _fixture(
        preferences: _preferences.copyWith(
          authTokens: const [
            UserAuthToken(id: 9, browser: 'Chrome', isActive: true),
          ],
        ),
      );
      await _pumpPage(tester, active);
      await _section(tester, PreferenceSection.security);
      expect(_session(9), findsOneWidget);
      expect(find.text('Chrome'), findsOneWidget);
      expect(_signOut(9), findsNothing);
    });

    testWidgets('its actions are named for a screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      final fixture = await _fixture(preferences: _sessions);
      await _pumpPage(tester, fixture);
      await _section(tester, PreferenceSection.security);

      expect(find.bySemanticsLabel('Open website: Password'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Open website: Two-factor authentication'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Open website: Passkeys'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Sign out Firefox on macOS'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('fits a phone at twice the text size', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final fixture = await _fixture(preferences: _sessions);
      await _pumpPage(tester, fixture, width: 320);
      await _section(tester, PreferenceSection.security);
      await tester.ensureVisible(_signOut(42));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.getRect(_session(41)).right, lessThanOrEqualTo(320));
      expect(tester.getRect(_signOut(42)).right, lessThanOrEqualTo(320));
    });
  });

  group('profile picture', () {
    testWidgets('a chosen image is uploaded, picked and read back', (
      tester,
    ) async {
      final fixture = await _fixture(preferences: _pictures);
      await _pumpPage(tester, fixture, pickPicture: _pickMe);
      expect(find.byKey(const ValueKey('preferences-avatar')), findsOneWidget);
      expect(_defaultPicture, findsNothing);
      await tester.enterText(_bioInput, 'Still typing');
      await tester.pumpAndSettle();
      final userReads = fixture.api.currentUserRequests.length;

      await tester.tap(_changePicture);
      await tester.pumpAndSettle();

      expect(fixture.api.avatarUploads, ['me.png']);
      expect(fixture.api.avatarPicks, [(username: 'reader', uploadId: 91)]);
      expect(fixture.api.currentUserRequests.length, userReads + 1);
      expect(_defaultPicture, findsOneWidget);
      expect(_pictureError, findsNothing);
      expect(
        tester.widget<EditableText>(_bioInput).controller.text,
        'Still typing',
      );
      expect(fixture.api.userPreferenceUpdates, isEmpty);
    });

    testWidgets('a new picture reloads a profile page already showing it', (
      tester,
    ) async {
      final fixture = await _fixture(preferences: _pictures);
      final asked = <String>[];
      fixture.api.userProfileHandler = (siteUrl, username) async {
        asked.add(username);
        return UserProfile(card: UserCard(id: 7, username: username));
      };
      await fixture.shell.userProfile.load(
        fixture.shell.instanceFor(_siteUrl)!,
        'reader',
      );
      await _pumpPage(tester, fixture, pickPicture: _pickMe);

      await tester.tap(_changePicture);
      await tester.pumpAndSettle();

      expect(asked, ['reader', 'reader']);
    });

    testWidgets('a new picture reaches what was loaded with the old one', (
      tester,
    ) async {
      const letter = '/letter_avatar_proxy/v4/letter/r/a587f6/{size}.png';
      const uploaded =
          '/user_avatar/preferences.example/reader/{size}/91_2.png';
      DiscourseUser reader(String template) => DiscourseUser(
        id: 7,
        username: 'reader',
        timezone: 'Etc/UTC',
        avatarTemplate: template,
      );
      final fixture = await _fixture(
        site: _site.copyWith(user: reader(letter)),
        apiOverride: FakeDiscourseApi(
          models: bundledPluginCodec,
          user: reader(letter),
          userPreferences: _pictures,
          cards: const {'reader': UserCard(id: 7, username: 'reader')},
        ),
      );
      fixture.api.avatarPickHandler = (_) async {
        fixture.api.accounts['api-key'] = reader(uploaded);
      };
      await fixture.shell.loadUserCard('reader', siteUrl: _siteUrl);
      await _pumpPage(tester, fixture, pickPicture: _pickMe);
      String? drawn(String username) => fixture.shell.ownAvatars.urlFor(
        _siteUrl,
        username,
        '$_siteUrl${letter.replaceAll('{size}', '90')}',
      );
      expect(drawn('reader'), '$_siteUrl${letter.replaceAll('{size}', '90')}');
      fixture.api.cardsRequested.clear();

      await tester.tap(_changePicture);
      await tester.pumpAndSettle();

      expect(
        drawn('reader'),
        '$_siteUrl${uploaded.replaceAll('{size}', '90')}',
      );
      expect(drawn('rival'), '$_siteUrl${letter.replaceAll('{size}', '90')}');
      expect(fixture.api.cardsRequested, [
        'reader',
      ], reason: 'the stored card of the reader is read again');
    });

    testWidgets('both actions wait while a change is on its way', (
      tester,
    ) async {
      final fixture = await _fixture(
        preferences: _pictures.copyWith(uploadedAvatarId: 4),
      );
      final upload = Completer<int>();
      final pick = Completer<void>();
      fixture.api
        ..avatarUploadHandler = ((_, _) => upload.future)
        ..avatarPickHandler = ((_) => pick.future);
      await _pumpPage(tester, fixture, pickPicture: _pickMe);

      await tester.tap(_changePicture);
      await tester.pump();
      await tester.pump();
      expect(tester.widget<DButton>(_changePicture).loading, isTrue);
      expect(tester.widget<DButton>(_changePicture).onPressed, isNull);
      expect(tester.widget<DButton>(_defaultPicture).onPressed, isNull);
      expect(find.text('Uploading…'), findsOneWidget);

      upload.complete(12);
      await tester.pump();
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      expect(tester.widget<DButton>(_changePicture).onPressed, isNull);

      pick.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<DButton>(_changePicture).loading, isFalse);
      expect(tester.widget<DButton>(_changePicture).onPressed, isNotNull);
      expect(tester.widget<DButton>(_defaultPicture).onPressed, isNotNull);
    });

    testWidgets('a refused image says why and can be tried again', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final fixture = await _fixture(preferences: _pictures);
      fixture.api.avatarUploadHandler = (_, _) async =>
          throw const ComposerUploadException(
            'Sorry, that image is too big.',
            statusCode: 422,
          );
      await _pumpPage(tester, fixture, pickPicture: _pickMe);

      await tester.tap(_changePicture);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(_pictureError),
        isSemantics(label: 'Sorry, that image is too big.', isLiveRegion: true),
      );
      expect(fixture.api.avatarPicks, isEmpty);
      expect(tester.widget<DButton>(_changePicture).onPressed, isNotNull);

      fixture.api.avatarUploadHandler = null;
      await tester.tap(_changePicture);
      await tester.pumpAndSettle();
      expect(_pictureError, findsNothing);
      expect(fixture.api.avatarPicks, hasLength(1));
      semantics.dispose();
    });

    testWidgets('use default returns to the letter avatar', (tester) async {
      final semantics = tester.ensureSemantics();
      final fixture = await _fixture(
        preferences: _pictures.copyWith(uploadedAvatarId: 4),
      );
      await _pumpPage(tester, fixture);
      expect(find.bySemanticsLabel('Use the default picture'), findsOneWidget);
      expect(find.bySemanticsLabel('Change picture'), findsOneWidget);

      await tester.tap(_defaultPicture);
      await tester.pumpAndSettle();

      expect(fixture.api.avatarUploads, isEmpty);
      expect(fixture.api.avatarPicks, [(username: 'reader', uploadId: null)]);
      expect(_defaultPicture, findsNothing);
      expect(_changePicture, findsOneWidget);
      semantics.dispose();
    });

    testWidgets('backing out of the picker changes nothing', (tester) async {
      final fixture = await _fixture(preferences: _pictures);
      await _pumpPage(tester, fixture, pickPicture: () async => null);

      await tester.tap(_changePicture);
      await tester.pumpAndSettle();

      expect(fixture.api.avatarUploads, isEmpty);
      expect(_pictureError, findsNothing);
      expect(tester.widget<DButton>(_changePicture).onPressed, isNotNull);
    });

    testWidgets('a picker the device refuses is reported', (tester) async {
      final fixture = await _fixture(preferences: _pictures);
      await _pumpPage(
        tester,
        fixture,
        pickPicture: () async => throw PlatformException(code: 'denied'),
      );

      await tester.tap(_changePicture);
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't open a picture from this device."),
        findsOneWidget,
      );
      expect(fixture.api.avatarUploads, isEmpty);
    });

    testWidgets('the row follows what the site allows', (tester) async {
      for (final (preferences, change, useDefault) in [
        (_pictures.copyWith(canEditAvatar: false, uploadedAvatarId: 4), 0, 0),
        (_pictures.copyWith(canUploadAvatar: false), 0, 0),
        (_pictures.copyWith(canUploadAvatar: false, uploadedAvatarId: 4), 0, 1),
        (_pictures, 1, 0),
      ]) {
        final fixture = await _fixture(preferences: preferences);
        await _pumpPage(tester, fixture);
        expect(_changePicture, findsNWidgets(change));
        expect(_defaultPicture, findsNWidgets(useDefault));
        expect(
          find.byType(PreferencesAvatarRow),
          findsNWidgets(change + useDefault == 0 ? 0 : 1),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('fits a phone at twice the text size', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final fixture = await _fixture(
        preferences: _pictures.copyWith(uploadedAvatarId: 4),
      );
      fixture.api.avatarPickHandler = (_) async => throw const WriteException(
        WriteFailure.validation,
        errors: ['You are not permitted to change your picture here.'],
      );
      await _pumpPage(tester, fixture, width: 320);
      await tester.tap(_defaultPicture);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_pictureError, findsOneWidget);
      expect(tester.getRect(_defaultPicture).right, lessThanOrEqualTo(320));
      expect(tester.getRect(_changePicture).right, lessThanOrEqualTo(320));
    });
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
  const loadingCases = [
    (320.0, Brightness.light, TargetPlatform.iOS),
    (320.0, Brightness.dark, TargetPlatform.macOS),
    (1000.0, Brightness.light, TargetPlatform.macOS),
    (1000.0, Brightness.dark, TargetPlatform.iOS),
  ];
  for (final (width, brightness, platform) in loadingCases) {
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
              (brightness == Brightness.dark ? AppTheme.dark : AppTheme.light)
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
        expect(_titleMark, findsOneWidget);
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

  testWidgets(
    'refresh retains preference fields beside an accessible skeleton',
    (tester) async {
      final api = _RefreshPreferencesApi();
      final fixture = await _fixture(apiOverride: api);
      await _pumpPage(tester, fixture);
      final field = tester.element(_timezoneMenu);
      api.refreshGate = Completer<void>();
      final refresh = fixture.shell.preferences.load(
        fixture.shell.currentInstance!,
        refresh: true,
      );
      await tester.pump();
      expect(find.text('Refreshing preferences…'), findsNothing);
      expect(find.byType(DSpinner), findsNothing);
      expect(find.byType(DSkeletonRegion), findsOneWidget);
      expect(
        tester
            .widget<DSkeletonRegion>(find.byType(DSkeletonRegion))
            .semanticsLabel,
        'Refreshing preferences…',
      );
      expect(identical(tester.element(_timezoneMenu), field), isTrue);

      api.refreshGate!.complete();
      await refresh;
      await tester.pumpAndSettle();
      expect(find.byType(DSkeletonRegion), findsNothing);
      expect(_timezoneMenu, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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
  testWidgets('lays the Chat row out like a core preference row', (
    tester,
  ) async {
    final fixture = await _fixture(site: _chatSite);
    await _pumpPage(tester, fixture, width: 1000);
    await _section(tester, PreferenceSection.interface);
    final coreSelect = tester.getRect(
      find.byType(DSelect<BookmarkAutoDeletePreference>),
    );
    final coreLabel = tester.getTopLeft(
      find.text('Automatically delete bookmarks'),
    );

    await _section(tester, chatPreferenceSection);

    expect(
      tester.getRect(find.byType(DSelect<ChatSeparateSidebarPreference>)),
      coreSelect,
    );
    expect(
      tester.getTopLeft(
        find.text('Show separate sidebar modes for forum and chat'),
      ),
      coreLabel,
    );
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
  testWidgets('the linked posts switch names the link it notifies about', (
    tester,
  ) async {
    final fixture = await _fixture();
    await _pumpPage(tester, fixture);
    await _section(tester, PreferenceSection.notifications);
    expect(
      [
        for (final text in tester.widgetList<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('notify-on-linked-posts')),
            matching: find.byType(Text),
          ),
        ))
          text.data,
      ],
      [
        'Notify when someone shares a link to one of my posts',
        'Turn this off to stop getting a notification for each link.',
      ],
    );
  });
  testWidgets('bookmark choices name what happens to the bookmark', (
    tester,
  ) async {
    final fixture = await _fixture();
    await _pumpPage(tester, fixture);
    await _section(tester, PreferenceSection.interface);
    final select = tester
        .widget<PreferenceSelect<BookmarkAutoDeletePreference>>(
          find.byType(PreferenceSelect<BookmarkAutoDeletePreference>),
        );
    expect(
      [
        for (final entry in select.entries)
          (entry as DSelectItem<BookmarkAutoDeletePreference>).textValue,
      ],
      [
        'Keep bookmark',
        'Delete after the reminder',
        'Delete once I reply',
        'Keep bookmark and clear reminder',
      ],
    );
  });
  testWidgets('server bookmark preference still mirrors after confirmation', (
    tester,
  ) async {
    final fixture = await _fixture();
    await _pumpPage(tester, fixture);
    await _section(tester, PreferenceSection.interface);
    expect(find.byType(HeaderTuningPreferences), findsOneWidget);
    await tester.tap(find.text('Keep bookmark and clear reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep bookmark').last);
    await tester.pumpAndSettle();
    expect(
      fixture.shell.instanceFor(_siteUrl)!.user!.bookmarkAutoDeletePreference,
      BookmarkAutoDeletePreference.never,
    );
  });
}

class _RefreshPreferencesApi extends FakeDiscourseApi {
  _RefreshPreferencesApi()
    : super(user: _chatSite.user, userPreferences: _preferences);

  Completer<void>? refreshGate;

  @override
  Future<UserPreferences> loadUserPreferences({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    await refreshGate?.future;
    return super.loadUserPreferences(
      siteUrl: siteUrl,
      apiKey: apiKey,
      username: username,
      clientId: clientId,
    );
  }
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
