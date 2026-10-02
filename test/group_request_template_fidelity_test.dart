import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/group_page.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'admin', admin: true);
const _raw = '    puts "hello"\n\nParagraph with a hard break  \n\n';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final editTemplate in [false, true]) {
    testWidgets(
      'Manage membership saves ${editTemplate ? 'typed' : 'loaded'} request template without changing its Markdown',
      (tester) async {
        final api = _GroupApi(editTemplate ? 'Existing description' : _raw);
        await pumpShell(
          tester,
          defaultTargetPlatform == TargetPlatform.macOS ? desktop : phone,
          instances: [instance('meta.discourse.org').copyWith(user: _user)],
          api: api,
          authenticator: FakeAuthenticator()..keys[_site] = 'key',
        );
        final shell = ShellScope.read(
          tester.element(find.byType(MainContent, skipOffstage: false).first),
        );
        expect(
          shell.openGroupUrl('$_site/g/support/manage/membership'),
          isTrue,
        );
        await tester.pumpAndSettle();
        expect(find.byType(GroupPage), findsOneWidget);
        final template = find.byKey(
          const ValueKey('group-field-membership_request_template'),
        );
        final loadedText = tester.widget<DTextarea>(template).controller!.text;
        if (editTemplate) {
          await tester.ensureVisible(template);
          await tester.enterText(template, _raw);
        }
        final emailDomains = find.byKey(
          const ValueKey('group-field-automatic_membership_email_domains'),
        );
        await tester.enterText(emailDomains, 'example.com');
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        final save = find.byKey(const ValueKey('save-group-membership'));
        final scrollable = find
            .descendant(
              of: find.byKey(
                const PageStorageKey('group-manage-membership-scroll'),
              ),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(save, 300, scrollable: scrollable);
        await tester.pumpAndSettle();
        expect(tester.widget<DButton>(save).onPressed, isNotNull);
        await tester.tap(save);
        await tester.pumpAndSettle();

        final write = api.pluginWrites.single;
        expect(write.path, '/groups/9.json');
        expect(write.method, 'PUT');
        final values = write.body['group']! as Map;
        expect(values['automatic_membership_email_domains'], 'example.com');
        expect(values['membership_request_template'], _raw);
        if (!editTemplate) expect(loadedText, _raw);
        expect(
          shell.groups
              .detailState(_site, 'support')
              .detail
              ?.group
              .membershipRequestTemplate,
          _raw,
        );
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

class _GroupApi extends FakeDiscourseApi {
  _GroupApi(String template)
    : group = {
        'id': 9,
        'name': 'support',
        'full_name': 'Support Team',
        'membership_request_template': template,
        'can_admin_group': true,
        'can_see_members': true,
        'allow_membership_requests': true,
      },
      super(user: _user, feeds: const {'/latest.json': []});

  final Map<String, dynamic> group;

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    if (Uri.parse(path).path == '/groups/support.json') {
      return {
        'group': {...group},
      };
    }
    return super.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String apiKey,
    required String method,
    required String path,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    pluginWrites.add((
      siteUrl: siteUrl,
      method: method,
      path: path,
      body: body,
    ));
    group.addAll((body['group']! as Map).cast<String, dynamic>());
    return {
      'group': {...group},
    };
  }
}
