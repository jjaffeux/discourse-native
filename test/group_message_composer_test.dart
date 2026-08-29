import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'message group opens and submits a native private-message composer',
    () async {
      final api = FakeDiscourseApi(feeds: const {'/latest.json': []});
      final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance('meta.discourse.org').copyWith(
            user: const DiscourseUser(
              id: 1,
              username: 'reader',
              canSendPrivateMessages: true,
            ),
          ),
        ]),
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      shell.pushContent(ContentRoute.group(GroupRoute.detail('tech-leads')));

      shell.openPrivateMessage(
        siteUrl: _siteUrl,
        targetRecipients: 'tech-leads',
      );

      final composer = shell.visibleComposer;
      expect(composer, isNotNull);
      expect(composer!.target.mode, ComposerMode.privateMessage);
      expect(composer.target.targetRecipients, 'tech-leads');
      expect(composer.target.draftKey, 'new_private_message');

      composer.title.text = 'A private subject';
      composer.text.text = 'Hello team';
      await shell.submitComposer();

      expect(api.topicsCreated, hasLength(1));
      expect(api.topicsCreated.single['title'], 'A private subject');
      expect(api.topicsCreated.single['raw'], 'Hello team');
      expect(api.topicsCreated.single['targetRecipients'], 'tech-leads');
      expect(api.topicsCreated.single['draftKey'], 'new_private_message');
      expect(shell.visibleComposer, isNull);
      expect(shell.currentContent?.topicId, 901);
    },
  );

  test(
    'private messaging remains unavailable without server permission',
    () async {
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance(
            'meta.discourse.org',
          ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
        ]),
        api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      shell.pushContent(ContentRoute.group(GroupRoute.detail('tech-leads')));

      shell.openPrivateMessage(
        siteUrl: _siteUrl,
        targetRecipients: 'tech-leads',
      );

      expect(shell.visibleComposer, isNull);
    },
  );
}
