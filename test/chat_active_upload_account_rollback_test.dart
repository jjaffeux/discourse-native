import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_composer.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream_target.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/blank_png.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
final _user = DiscourseUser(
  id: 1,
  username: 'staff',
  staff: true,
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);
const _channel = ChatChannel(
  id: 9,
  title: 'Support',
  kind: ChatChannelKind.category,
  membership: ChatMembership(following: true),
);

enum _Operation { unchanged, failedReconnect, failedDisconnect }

enum _Stage { preparation, response }

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final stage in _Stage.values) {
    for (final operation in _Operation.values) {
      testWidgets(
        'active upload ${stage.name} ${operation.name} belongs to its opening account',
        (tester) async {
          final previousFiles = FileSelectorPlatform.instance;
          final gate = Completer<void>();
          final selection = _FileSelector(
            stage == _Stage.preparation ? gate.future : null,
          );
          FileSelectorPlatform.instance = selection;
          try {
            final site = instance('meta.discourse.org').copyWith(user: _user);
            final store = _FailingStore([site]);
            final api = _UploadApi(
              response: stage == _Stage.response ? gate.future : null,
            );
            addTearDown(api.uploadApi.close);
            await pumpShell(
              tester,
              defaultTargetPlatform == TargetPlatform.macOS ? desktop : phone,
              instances: [site],
              store: store,
              api: api,
              authenticator: FakeAuthenticator()..keys[_site] = 'key',
            );
            final shell = ShellScope.read(tester.element(primaryMainContent));
            await shell.chat.loadChannels(_site);
            expect(shell.openChatChannel(9), isTrue);
            await tester.pumpAndSettle();
            final composerView = find.byType(ChatComposer);
            final composerState = tester.state(composerView);
            await _pick(tester);
            expect(selection.requests, 1);
            final queue = tester.widget<ComposerUploadQueue>(
              find.byType(ComposerUploadQueue),
            );
            final composer = queue.composer;
            expect(
              composer.uploads.single.status,
              stage == _Stage.preparation
                  ? ComposerUploadStatus.processing
                  : ComposerUploadStatus.uploading,
            );
            expect(api.requests, hasLength(stage == _Stage.response ? 1 : 0));
            final lease = shell.chat.captureSession(_site);
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
              expect(shell.currentInstance?.user?.id, 1);
              expect(lease.isCurrent, isFalse);
              await shell.chat.loadChannels(_site);
              await shell.chat.openChannel(_site, 9, force: true);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 300));
              expect(tester.state(composerView), same(composerState));
              expect(shell.chat.canSendMessage(_site, 9), isTrue);
              // This new-account draft must not acquire the previous session's
              // upload when its platform work or HTTP response later completes.
              composer.text.text = 'Replacement account draft';
              await tester.pump();
            }
            gate.complete();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            final expectedWrites = stage == _Stage.response || !rollsBack
                ? 1
                : 0;
            expect(api.requests, hasLength(expectedWrites));
            expect(composer.completedUploads, hasLength(rollsBack ? 0 : 1));
            expect(composer.hasActiveUploads, isFalse);
            const target = ChatChannelTarget(9);
            if (rollsBack) {
              expect(composer.raw, 'Replacement account draft');
              expect(
                shell.chat.composerDraftFor(_site, target)?.uploads,
                isEmpty,
              );
              expect(
                shell.chat.composerDraftFor(_site, target)?.raw,
                'Replacement account draft',
              );
              expect(composer.uploads, isEmpty);
              // A fresh native selection still uploads and joins this draft.
              selection.preparation = null;
              await _pick(tester);
              expect(selection.requests, 2);
              expect(api.requests, hasLength(expectedWrites + 1));
              expect(composer.completedUploads.single.id, 31);
              expect(composer.raw, 'Replacement account draft');
            } else {
              expect(composer.completedUploads.single.id, 31);
              expect(
                shell.chat.composerDraftFor(_site, target)?.uploads.single.id,
                31,
              );
            }
            final request = api.requests.last;
            expect(request.method, 'POST');
            expect(request.url, Uri.parse('$_site/uploads.json'));
            expect(request.headers['User-Api-Key'], 'key');
            expect(
              utf8.decode(request.bodyBytes, allowMalformed: true),
              contains('filename="selected.png"'),
            );
            expect(tester.takeException(), isNull);
          } finally {
            if (!gate.isCompleted) gate.complete();
            FileSelectorPlatform.instance = previousFiles;
          }
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

Future<void> _pick(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('chat-composer-add')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byKey(const ValueKey('chat-composer-upload')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

class _FileSelector extends FileSelectorPlatform {
  _FileSelector(this.preparation);
  Future<void>? preparation;
  int requests = 0;

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    requests++;
    return [_File(preparation)];
  }
}

class _File extends XFile {
  _File(this.preparation)
    : super.fromData(blankPng(width: 20, height: 20), path: 'selected.png');
  final Future<void>? preparation;

  @override
  Future<int> length() async {
    await preparation;
    return super.length();
  }
}

class _UploadApi extends FakeDiscourseApi {
  _UploadApi({Future<void>? response})
    : super(
        user: _user,
        feeds: const {'/latest.json': []},
        chatChannelsBySite: const {
          _site: ChatChannels(public: [_channel], direct: []),
        },
        chatChannelsById: const {9: _channel},
        chatMessagesByKey: const {
          '9': (
            messages: [],
            canLoadMorePast: false,
            canLoadMoreFuture: false,
            targetMessageId: null,
          ),
        },
      ) {
    uploadApi = DiscourseApi(
      client: MockClient((request) async {
        requests.add(request);
        await response;
        return http.Response(
          jsonEncode({
            'id': 31,
            'original_filename': 'selected.png',
            'short_url': 'upload://selected',
            'url': '/uploads/selected.png',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  }

  late final DiscourseApi uploadApi;
  final requests = <http.Request>[];

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
  }) => uploadApi.uploadComposerImage(
    siteUrl: siteUrl,
    apiKey: apiKey,
    file: file,
    onProgress: onProgress,
    abortTrigger: abortTrigger,
    uploadType: uploadType,
    forPrivateMessage: forPrivateMessage,
    sizeLimit: sizeLimit,
    clientId: clientId,
  );
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
