import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/composer_syntax.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a held preparer synchronously blocks duplicate Send and uploads',
    () async {
      final gate = Completer<PluginComposerSubmitPreparation>();
      var preparations = 0;
      final api = _SubmissionApi();
      final fixture = await _openShell(
        api,
        preparers: [
          _Preparer((_) {
            preparations++;
            return gate.future;
          }),
        ],
      );
      final shell = fixture.shell;
      final composer = await _openReply(shell, 7);
      composer.text.text = _body;

      final submitting = shell.submitComposer(composer: composer);
      final duplicate = shell.submitComposer(composer: composer);
      addTearDown(() async {
        if (!gate.isCompleted) {
          gate.complete(const PluginComposerSubmitPreparation.proceed());
        }
        await Future.wait([submitting, duplicate]);
      });

      expect(composer.submitting, isTrue);
      expect(composer.canSubmit, isFalse);
      expect(composer.canUpload, isFalse);
      expect(preparations, 1);
      expect(api.created, isEmpty);

      composer.addImages([_file('during-preparation.png')], 0);
      composer.addFiles([_file('during-preparation.txt')], 0);
      expect(composer.uploads, isEmpty);
      expect(composer.raw, _body);
      await Future<void>.delayed(Duration.zero);
      expect(api.uploadedNames, isEmpty);
      expect(api.created, isEmpty);

      gate.complete(const PluginComposerSubmitPreparation.proceed());
      await Future.wait([submitting, duplicate]);

      expect(preparations, 1);
      expect(api.created, hasLength(1));
      expect(api.created.single['raw'], _body);
      expect(api.created.single['topicId'], 7);
      expect(api.uploadedNames, isEmpty);
      expect(shell.visibleComposer, isNull);
      expect(composer.isDisposed, isTrue);
    },
  );

  for (final refusal in _PreparationRefusal.values) {
    test(
      'prepared text remains durable when a later preparer ${refusal.name}',
      () async {
        final api = _SubmissionApi();
        final observedByLaterPreparer = <String>[];
        final fixture = await _openShell(
          api,
          preparers: [
            _Preparer((composer) {
              final before = composer.value;
              expect(
                composer.commit(
                  expectedValue: before,
                  value: TextEditingValue(
                    text: _preparedBody,
                    selection: TextSelection.collapsed(
                      offset: _preparedBody.length,
                    ),
                  ),
                ),
                isTrue,
              );
              return const PluginComposerSubmitPreparation.proceed(
                changed: true,
              );
            }),
            _Preparer((composer) {
              observedByLaterPreparer.add(composer.value.text);
              return switch (refusal) {
                _PreparationRefusal.refuses =>
                  const PluginComposerSubmitPreparation.failed(
                    _preparationFailure,
                  ),
                _PreparationRefusal.throwsError => throw StateError(
                  'Preparation failed',
                ),
              };
            }),
          ],
        );
        final shell = fixture.shell;
        final composer = await _openReply(shell, 7);
        composer.text.text = _body;

        await shell.submitComposer(composer: composer);

        expect(observedByLaterPreparer, [_preparedBody]);
        expect(api.created, isEmpty);
        expect(shell.visibleComposer, same(composer));
        expect(composer.raw, _preparedBody);
        expect(
          fixture.drafts.events
              .where((event) => event.startsWith('write:'))
              .map((event) => ComposerDraft.decode(event.substring(6))?.reply),
          contains(_preparedBody),
        );
        expect(
          shell.store.read<TopicDetail>(_site, 7)?.draft?.reply,
          _preparedBody,
        );
        expect(api.draftsSaved, isNotEmpty);
        expect(
          ComposerDraft.decode(api.draftsSaved.last['data'])?.reply,
          _preparedBody,
        );
        expect(composer.error, isA<WriteException>());
        expect(composer.submitting, isFalse);
        expect(composer.canRecheck, isFalse);
        expect(composer.isEditing, isTrue);
        expect(composer.canSubmit, isTrue);
        expect(composer.canUpload, isTrue);

        composer.text.text = _editedBody;
        expect(composer.raw, _editedBody);
        await composer.flushDraft();
        expect(
          ComposerDraft.decode(api.draftsSaved.last['data'])?.reply,
          _editedBody,
        );
        expect(
          shell.store.read<TopicDetail>(_site, 7)?.draft?.reply,
          _editedBody,
        );
        expect(api.created, isEmpty);
      },
    );
  }

  test(
    'Check again keeps the sent raw and preserves another selected editor',
    () async {
      final api = _SubmissionApi(
        writeFailure: const WriteException(WriteFailure.unreachable),
      );
      final fixture = await _openShell(api);
      final shell = fixture.shell;
      final first = await _openReply(shell, 7);
      first.text.text = _body;

      await shell.submitComposer(composer: first);
      expect(api.created, hasLength(1));
      expect(first.canRecheck, isTrue);

      first.text.text = 'Text changed after the response was lost.';
      await first.flushDraft();
      shell.createTab();
      final selectedTab = shell.activeTabId;
      final selected = await _openReply(shell, 8);
      const selectedValue = TextEditingValue(
        text: 'Keep this second reply and its selection.',
        selection: TextSelection(baseOffset: 5, extentOffset: 9),
      );
      selected.text.value = selectedValue;
      await selected.flushDraft();
      api.topics[7] = topicPayload(
        id: 7,
        title: 'Topic 7',
        stream: const [22],
        postsCount: 1,
        canCreatePost: true,
      );
      api.postsById[22] = const Post(
        id: 22,
        postNumber: 2,
        username: 'author',
        cooked: '<p>$_body</p>',
        raw: _body,
      );

      await shell.recheckComposer(composer: first);

      expect(api.created, hasLength(1));
      expect(api.created.single['raw'], _body);
      expect(api.created.single['topicId'], 7);
      expect(first.isDisposed, isTrue);
      expect(shell.liveComposers, isNot(contains(first)));
      expect(shell.activeTabId, selectedTab);
      expect(shell.currentContent?.topicId, 8);
      expect(shell.visibleComposer, same(selected));
      expect(selected.text.value, selectedValue);
      expect(selected.isEditing, isTrue);
    },
  );
}

Future<({ShellController shell, FakeDraftStore drafts})> _openShell(
  _SubmissionApi api, {
  List<PluginComposerSubmitPreparer> preparers = const [],
}) async {
  final plugins = PluginInstaller.install(
    PluginManifest([_PreparerModule(preparers)]),
  );
  addTearDown(plugins.close);
  final drafts = FakeDraftStore();
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 7, username: 'author')),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
    drafts: drafts,
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: plugins,
  );
  addTearDown(shell.dispose);
  await shell.load();
  await shell.resolveSiteConfig(_site);
  return (shell: shell, drafts: drafts);
}

Future<ComposerController> _openReply(
  ShellController shell,
  int topicId,
) async {
  shell.store.put(
    _site,
    TopicDetail(
      id: topicId,
      title: 'Topic $topicId',
      stream: const [],
      canCreatePost: true,
    ),
  );
  shell.pushContent(
    ContentRoute.topic(
      topicId: topicId,
      slug: 'topic-$topicId',
      title: 'Topic $topicId',
    ),
  );
  shell.openReply();
  final composer = shell.visibleComposer!;
  await shell.finishComposerDraftRestore(composer);
  return composer;
}

final class _PreparerModule implements PluginModule {
  const _PreparerModule(this.preparers);

  final List<PluginComposerSubmitPreparer> preparers;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('submission-test'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addSession(
      (_, _) => PluginSessionContribution(
        lifecycle: _PreparerLifecycle(),
        capabilities: preparers,
      ),
    );
  }
}

final class _PreparerLifecycle extends PluginSessionLifecycle {}

final class _Preparer implements PluginComposerSubmitPreparer {
  const _Preparer(this.prepare);

  final FutureOr<PluginComposerSubmitPreparation> Function(ComposerEditorHost)
  prepare;

  @override
  FutureOr<PluginComposerSubmitPreparation> prepareComposerSubmit(
    ComposerEditorHost composer,
  ) => prepare(composer);
}

final class _SubmissionApi extends FakeDiscourseApi {
  _SubmissionApi({WriteException? writeFailure})
    : super(
        feeds: const {'/latest.json': []},
        user: const DiscourseUser(id: 7, username: 'author'),
        topics: {},
        postsById: {},
        writeFailure: writeFailure,
        siteConfigs: const {
          _site: SiteConfig(authorizedExtensions: ['png', 'txt']),
        },
      );

  final uploadedNames = <String>[];

  @override
  Future<ComposerUploadResult> uploadComposerImage({
    required String siteUrl,
    required String apiKey,
    required ComposerUploadFile file,
    required void Function(double progress) onProgress,
    required Future<void> abortTrigger,
    ComposerUploadType uploadType = ComposerUploadType.composer,
    bool forPrivateMessage = false,
    ComposerUploadSizeLimit? sizeLimit,
    String? clientId,
  }) async {
    uploadedNames.add(file.name);
    return ComposerUploadResult(
      id: uploadedNames.length,
      originalFilename: file.name,
      shortUrl: 'upload://${file.name}',
      url: '$_site/uploads/${file.name}',
    );
  }
}

ComposerUploadFile _file(String name) => ComposerUploadFile(
  name: name,
  length: () => Future.value(3),
  openRead: () => Stream.value([1, 2, 3]),
);

enum _PreparationRefusal { refuses, throwsError }

const _site = 'https://meta.discourse.org';
const _body = 'A post ready for the original submission.';
const _preparedBody = 'A transformed post that must remain in the draft.';
const _editedBody = 'The author can edit again after preparation fails.';
const _preparationFailure = WriteException(
  WriteFailure.validation,
  errors: ['The later preparer refused this post.'],
);
