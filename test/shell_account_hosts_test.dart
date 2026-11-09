import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/header_preferences.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

final class _ScriptedAccount extends ShellController {
  _ScriptedAccount()
    : super(
        instanceStore: FakeInstanceStore(const []),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
      );

  DiscourseInstance? _account;

  @override
  DiscourseInstance? get currentInstance => _account;

  void signIn(DiscourseInstance account) {
    _account = account;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'a user id arriving later moves the hosts to the right document',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final shell = _ScriptedAccount();
      addTearDown(shell.dispose);
      late BuildContext reader;
      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: Builder(
            builder: (context) {
              reader = context;
              return const SizedBox();
            },
          ),
        ),
      );

      final site = instance('one.example');
      shell.signIn(
        site.copyWith(user: const DiscourseUser(username: 'reader')),
      );
      await tester.pump();
      final withoutId = HeaderPreferencesHost.maybeOf(reader);
      expect(withoutId, isNotNull);

      shell.signIn(
        site.copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
      );
      await tester.pump();

      expect(HeaderPreferencesHost.maybeOf(reader), isNot(same(withoutId)));
    },
  );
}
