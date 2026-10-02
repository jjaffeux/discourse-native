import 'dart:convert';
import 'dart:ui' show Size;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/do_not_disturb.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://forum.example';
final _user = _reader(7, 'reader');
final _replacement = _reader(8, 'replacement');

DiscourseUser _reader(int id, String username) => DiscourseUser(
  id: id,
  username: username,
  hidePresence: false,
  doNotDisturbUntil: eternalDoNotDisturbUntil,
);

final class _Authenticator extends FakeAuthenticator {
  _Authenticator(this.transition)
    : super(
        credentials: const UserApiCredentials(
          key: 'replacement-key',
          apiVersion: 4,
          push: false,
        ),
        failure: transition == 'cancelled reconnect'
            ? UserApiAuthFailure.cancelled
            : null,
      );
  final String transition;

  @override
  Future<void> persistCredentials(
    String siteUrl,
    UserApiCredentials credentials,
  ) async {
    if (transition == 'connect rollback') {
      throw StateError('Keychain refused replacement');
    }
    await super.persistCredentials(siteUrl, credentials);
  }
}

final class _Instances extends FakeInstanceStore {
  _Instances() : super([instance('forum.example').copyWith(user: _user)]);
  bool rejectSignedOut = false;

  @override
  Future<void> save(List<DiscourseInstance> instances) async {
    if (rejectSignedOut && instances.any((site) => site.user == null)) {
      throw StateError('Preferences refused signed-out snapshot');
    }
    await super.save(instances);
  }
}

final class _Api extends FakeDiscourseApi {
  _Api(this.writer) : super(user: _user) {
    accounts['replacement-key'] = _replacement;
  }
  final DiscourseApi writer;

  @override
  Future<void> updateHidePresence({
    required String siteUrl,
    required String apiKey,
    required String username,
    required bool hidePresence,
    String? clientId,
  }) => writer.updateHidePresence(
    siteUrl: siteUrl,
    apiKey: apiKey,
    username: username,
    hidePresence: hidePresence,
    clientId: clientId,
  );

  @override
  Future<void> leaveDoNotDisturb({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) => writer.leaveDoNotDisturb(
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Native profile toggles fit a narrow phone with enlarged text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final client = MockClient((_) async => http.Response('{}', 200));
    addTearDown(client.close);
    await pumpShell(
      tester,
      const Size(320, 844),
      store: _Instances(),
      api: _Api(DiscourseApi(client: client)),
      authenticator: _Authenticator('unchanged')..keys[_site] = 'old-key',
    );
    await tester.tap(find.byKey(UserMenuButton.avatarKey));
    await tester.pumpAndSettle();
    for (final key in ['user-menu-hide-presence', 'pause-notifications-row']) {
      final control = find.byKey(ValueKey(key));
      expect(tester.widget(control), isA<DToggle>());
      expect(tester.widget<DToggle>(control).enabled, isTrue);
      expect(tester.getRect(control).left, greaterThanOrEqualTo(0));
      expect(tester.getRect(control).right, lessThanOrEqualTo(320));
    }
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  for (final presence in [true, false]) {
    for (final transition in [
      'unchanged',
      'reconnect',
      'connect rollback',
      'disconnect rollback',
      'cancelled reconnect',
    ]) {
      testWidgets(
        'Native ${presence ? 'presence' : 'DND resume'} control owns its rendered account after $transition',
        (tester) async {
          final sent = <http.Request>[];
          final client = MockClient((request) async {
            sent.add(request);
            return http.Response(jsonEncode({}), 200);
          });
          addTearDown(client.close);
          final instances = _Instances();
          final auth = _Authenticator(transition)..keys[_site] = 'old-key';
          await pumpShell(
            tester,
            defaultTargetPlatform == TargetPlatform.macOS ? desktop : phone,
            store: instances,
            api: _Api(DiscourseApi(client: client)),
            authenticator: auth,
          );
          await tester.tap(find.byKey(UserMenuButton.avatarKey));
          await tester.pumpAndSettle();
          final control = find.byKey(
            ValueKey(
              presence ? 'user-menu-hide-presence' : 'pause-notifications-row',
            ),
          );
          if (defaultTargetPlatform == TargetPlatform.macOS) {
            expect(tester.widget(control), isA<DDropdownMenuCheckboxItem>());
          } else {
            expect(tester.widget(control), isA<DToggle>());
          }
          final source = tester.element(control);
          final shell = ShellScope.read(tester.element(control));
          final lease = shell.lifecycle.capture(_site);
          if (transition == 'disconnect rollback') {
            instances.rejectSignedOut = true;
            expect(await shell.disconnectInstance(_site), isFalse);
          } else if (transition != 'unchanged') {
            await shell.connectCurrentInstance();
          }
          final retired =
              transition != 'unchanged' && transition != 'cancelled reconnect';
          expect(lease.isCurrent, !retired);
          expect(
            auth.keys[_site],
            transition == 'reconnect' ? 'replacement-key' : 'old-key',
          );
          expect(
            shell.currentInstance?.user,
            transition == 'reconnect' ? _replacement : _user,
          );
          expect(tester.element(control), same(source));
          expect(shell.hidePresenceFor(_site), isFalse);
          expect(
            shell.doNotDisturb.stateFor(_site).isActiveAt(DateTime.now()),
            isTrue,
          );
          await tester.tap(control);
          await tester.pumpAndSettle();
          if (retired) {
            expect(sent, isEmpty);
            expect(shell.hidePresenceFor(_site), isFalse);
            expect(
              shell.doNotDisturb.stateFor(_site).isActiveAt(DateTime.now()),
              isTrue,
            );
            await tester.tap(control);
            await tester.pumpAndSettle();
          }
          expect(sent.single.headers['user-api-key'], auth.keys[_site]);
          if (presence) {
            expect(sent.single.method, 'PUT');
            expect(
              sent.single.url.path,
              '/u/${shell.currentInstance!.user!.username}.json',
            );
            expect(jsonDecode(sent.single.body), {'hide_presence': true});
            expect(shell.hidePresenceFor(_site), isTrue);
          } else {
            expect(sent.single.method, 'DELETE');
            expect(sent.single.url.path, '/do-not-disturb.json');
            expect(
              shell.doNotDisturb.stateFor(_site).isActiveAt(DateTime.now()),
              isFalse,
            );
          }
          expect(tester.takeException(), isNull);
        },
        variant: const TargetPlatformVariant({
          TargetPlatform.macOS,
          TargetPlatform.android,
        }),
      );
    }
  }
}
