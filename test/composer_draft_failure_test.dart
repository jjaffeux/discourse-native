import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a failed local write still gives the server a chance', (
    tester,
  ) async {
    final opened = await _openComposer();
    addTearDown(opened.shell.dispose);

    opened.composer.text.text = 'Safe on the site';
    await opened.composer.flushDraft();

    expect(opened.api.draftsSaved, hasLength(1));
    expect(opened.composer.draftStatus, DraftStatus.saved);
    expect(opened.composer.localDraftFailed, isFalse);
  });

  testWidgets('the panel reports when neither draft copy is safe', (
    tester,
  ) async {
    final opened = await _openComposer(
      remoteFailure: const WriteException(WriteFailure.unreachable),
    );
    addTearDown(opened.shell.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ShellScope(
          controller: opened.shell,
          child: Scaffold(body: ComposerPanel(composer: opened.composer)),
        ),
      ),
    );

    opened.composer.text.text = 'Not safe yet';
    await opened.composer.flushDraft();
    await tester.pump();

    expect(opened.api.draftsSaved, hasLength(1));
    expect(opened.composer.localDraftFailed, isTrue);
    expect(
      find.text("Couldn't save this draft on this device."),
      findsOneWidget,
    );
    expect(
      find.text('Not saved on the site — kept on this device only.'),
      findsNothing,
    );
  });
}

Future<
  ({ShellController shell, FakeDiscourseApi api, ComposerController composer})
>
_openComposer({WriteException? remoteFailure}) async {
  final api = FakeDiscourseApi(draftFailure: remoteFailure);
  final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
  final connected = instance(
    'meta.discourse.org',
  ).copyWith(user: const DiscourseUser(id: 1, username: 'reader'));
  final shell = ShellController(
    instanceStore: FakeInstanceStore([connected]),
    api: api,
    authenticator: authenticator,
    drafts: _FailingDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );

  await shell.load();
  shell.store.put(
    _siteUrl,
    const TopicDetail(id: 7, title: 'A topic', stream: [], canCreatePost: true),
  );
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
  );
  shell.openReply();
  return (shell: shell, api: api, composer: shell.visibleComposer!);
}

final class _FailingDraftStore extends FakeDraftStore {
  @override
  Future<void> write(
    String siteUrl,
    String draftKey,
    String data, {
    bool Function()? ifCurrent,
  }) async {
    throw StateError('secure storage unavailable');
  }
}
