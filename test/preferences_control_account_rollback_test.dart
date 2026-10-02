import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/foundation/timezone_environment.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_preferences.dart';
import 'package:discourse_native/src/shell/preferences_page.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
final _user = DiscourseUser(
  id: 7,
  username: 'reader',
  timezone: 'Etc/UTC',
  plugins: const DiscourseUser(id: 7, username: 'reader').plugins.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(
      hasChatEnabled: true,
      canChat: true,
      canDirectMessage: true,
    ),
  ),
);
const _preferences = UserPreferences(
  username: 'reader',
  timezone: 'Etc/UTC',
  notifyOnLinkedPosts: true,
  canEdit: true,
  canChangeTrackingPreferences: true,
  pluginValues: {
    'chat/preferences': ChatUserPreferences(
      separateSidebarMode: ChatSeparateSidebarPreference.fullscreen,
    ),
  },
);

enum _Operation { unchanged, failedReconnect, failedDisconnect }

enum _Control { timezone, notify, plugin }

void main() {
  setUpAll(TimezoneEnvironment.instance.ensureDatabase);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final operation in _Operation.values) {
    for (final control in _Control.values) {
      for (final repaint in [
        false,
        if (operation != _Operation.unchanged && control != _Control.notify)
          true,
      ]) {
        testWidgets(
          'Native ${control.name} control ${operation.name} ${repaint ? 'after repaint' : 'before repaint'} owns its rendered account',
          (tester) async {
            final site = instance('meta.discourse.org').copyWith(user: _user);
            final store = _FailingStore([site]);
            final api = FakeDiscourseApi(
              user: _user,
              userPreferences: _preferences,
              feeds: const {'/latest.json': []},
            );
            await pumpShell(
              tester,
              defaultTargetPlatform == TargetPlatform.macOS ? desktop : phone,
              instances: [site],
              store: store,
              api: api,
              authenticator: FakeAuthenticator()..keys[_site] = 'key',
            );
            final shell = ShellScope.read(tester.element(primaryMainContent));
            shell.openPreferences(_site);
            await tester.pumpAndSettle();
            final pageState = tester.state(find.byType(PreferencesPage));
            final lease = shell.lifecycle.capture(_site);
            await _open(tester, control);
            final rollsBack = operation != _Operation.unchanged;
            if (rollsBack) {
              store.failSignedOut = true;
              if (operation == _Operation.failedDisconnect) {
                expect(
                  await tester.runAsync(() => shell.disconnectInstance(_site)),
                  isFalse,
                );
              } else {
                await tester.runAsync(shell.connectCurrentInstance);
              }
              expect(shell.currentContent?.isPreferences, isTrue);
              expect(shell.currentInstance?.user?.id, 7);
              expect(lease.isCurrent, isFalse);
              api.userPreferences = _preferences.copyWith(
                timezone: 'Asia/Tokyo',
              );
              await shell.preferences.load(shell.currentInstance!);
              expect(
                shell.preferences.stateFor(_site)!.draft!.timezone,
                'Asia/Tokyo',
              );
              expect(
                shell.preferences.stateFor(_site)!.confirmed!.timezone,
                'Asia/Tokyo',
              );
              // The public storage failure and restored load can complete before
              // the next frame, leaving the old Native control available to tap.
            }
            if (repaint) {
              await _pump(tester);
              expect(
                find.text(
                  control == _Control.timezone ? 'Europe/London' : 'Always',
                ),
                findsNothing,
              );
            } else {
              await _choose(tester, control);
            }
            final draft = shell.preferences.stateFor(_site)!.draft!;
            if (rollsBack) {
              expect(_chosen(draft, control), isFalse);
              expect(api.userPreferenceUpdates, isEmpty);
              await _pump(tester);
              expect(
                tester.state(find.byType(PreferencesPage)),
                same(pageState),
              );
              await _open(tester, control);
              await _choose(tester, control);
            }
            expect(
              _chosen(shell.preferences.stateFor(_site)!.draft!, control),
              isTrue,
            );
            await _pump(tester);
            final save = find.byKey(const ValueKey('preferences-save'));
            await tester.ensureVisible(save);
            await _pump(tester);
            await tester.tap(save);
            await _pump(tester);
            expect(api.userPreferenceUpdates, hasLength(1));
            expect(api.userPreferenceUpdates.single.values, switch (control) {
              _Control.timezone => {'timezone': 'Europe/London'},
              _Control.notify => {'notify_on_linked_posts': false},
              _Control.plugin => {'chat_separate_sidebar_mode': 'always'},
            });
            expect(tester.takeException(), isNull);
          },
          variant: const TargetPlatformVariant({
            TargetPlatform.iOS,
            TargetPlatform.android,
            TargetPlatform.macOS,
          }),
        );
      }
    }
  }
}

bool _chosen(UserPreferences draft, _Control control) => switch (control) {
  _Control.timezone => draft.timezone == 'Europe/London',
  _Control.notify => !draft.notifyOnLinkedPosts,
  _Control.plugin =>
    (draft.pluginValues['chat/preferences'] as ChatUserPreferences)
            .separateSidebarMode ==
        ChatSeparateSidebarPreference.always,
};

Finder get _timezone => find.byKey(const ValueKey('preferences-timezone'));
Future<void> _open(WidgetTester tester, _Control control) async {
  final target = switch (control) {
    _Control.timezone => _timezone,
    _Control.notify => find.byKey(const ValueKey('notify-on-linked-posts')),
    _Control.plugin => find.byType(DSelect<ChatSeparateSidebarPreference>),
  };
  await tester.ensureVisible(target);
  await _pump(tester);
  switch (control) {
    case _Control.timezone:
      await tester.tap(_timezone);
      await tester.enterText(
        find.descendant(of: _timezone, matching: find.byType(EditableText)),
        'Europe/Lond',
      );
    case _Control.plugin:
      await tester.tap(find.text('When chat is in fullscreen'));
    case _Control.notify:
      break;
  }
  await _pump(tester);
}

Future<void> _choose(WidgetTester tester, _Control control) =>
    tester.tap(switch (control) {
      _Control.timezone => find.text('Europe/London').last,
      _Control.notify => find.byKey(const ValueKey('notify-on-linked-posts')),
      _Control.plugin => find.text('Always').last,
    });

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

class _FailingStore extends FakeInstanceStore {
  _FailingStore(super.instances);
  bool failSignedOut = false;
  @override
  Future<void> save(List<DiscourseInstance> instances) {
    if (failSignedOut && instances.any((site) => site.user == null)) {
      return Future.error(StateError('Account snapshot unavailable'));
    }
    return super.save(instances);
  }
}
