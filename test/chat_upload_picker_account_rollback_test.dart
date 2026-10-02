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
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart'
    as images;
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final photos in [false, true]) {
    for (final operation in _Operation.values) {
      testWidgets(
        '${photos ? 'photo' : 'file'} picker ${operation.name} owns its opening account',
        (tester) async {
          final previousFiles = FileSelectorPlatform.instance;
          final previousPhotos = images.ImagePickerPlatform.instance;
          final selection = _HeldSelection();
          FileSelectorPlatform.instance = _HeldFileSelector(selection);
          images.ImagePickerPlatform.instance = _HeldImagePicker(selection);
          try {
            final site = instance('meta.discourse.org').copyWith(user: _user);
            final store = _FailingStore([site]);
            final api = _UploadApi();
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
            final composer = find.byType(ChatComposer);
            final composerState = tester.state(composer);
            await _openPicker(tester, photos: photos);
            expect(selection.requests, 1);
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
              expect(tester.state(composer), same(composerState));
              expect(shell.chat.canSendMessage(_site, 9), isTrue);
            }
            selection.complete();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(api.requests, hasLength(rollsBack ? 0 : 1));
            expect(
              find.byType(ComposerUploadQueue),
              rollsBack ? findsNothing : findsOneWidget,
            );
            if (rollsBack) {
              // Retiring the old selection must still let this account pick
              // and upload a fresh file through the same retained composer.
              selection.next();
              await _openPicker(tester, photos: photos);
              expect(selection.requests, 2);
              selection.complete();
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 300));
              expect(api.requests, hasLength(1));
              expect(find.byType(ComposerUploadQueue), findsOneWidget);
            }
            final request = api.requests.single;
            expect(request.method, 'POST');
            expect(request.url, Uri.parse('$_site/uploads.json'));
            expect(request.headers['User-Api-Key'], 'key');
            final multipart = utf8.decode(
              request.bodyBytes,
              allowMalformed: true,
            );
            expect(multipart, contains('filename="selected.png"'));
            expect(
              multipart,
              contains('name="upload_type"\r\n\r\nchat-composer'),
            );
            final queue = tester.widget<ComposerUploadQueue>(
              find.byType(ComposerUploadQueue),
            );
            expect(queue.composer.completedUploads.single.id, 31);
            expect(queue.composer.hasActiveUploads, isFalse);
            expect(tester.takeException(), isNull);
          } finally {
            selection.cancel();
            FileSelectorPlatform.instance = previousFiles;
            images.ImagePickerPlatform.instance = previousPhotos;
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

Future<void> _openPicker(WidgetTester tester, {required bool photos}) async {
  await tester.tap(find.byKey(const ValueKey('chat-composer-add')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(
    find.byKey(
      ValueKey(photos ? 'chat-composer-photos' : 'chat-composer-upload'),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

class _HeldSelection {
  Completer<List<XFile>> response = Completer<List<XFile>>();
  int requests = 0;

  Future<List<XFile>> pick() {
    requests++;
    return response.future;
  }

  void complete() => response.complete([
    XFile.fromData(blankPng(width: 20, height: 20), path: 'selected.png'),
  ]);

  void next() => response = Completer<List<XFile>>();

  void cancel() {
    if (!response.isCompleted) response.complete([]);
  }
}

class _HeldFileSelector extends FileSelectorPlatform {
  _HeldFileSelector(this.selection);
  final _HeldSelection selection;

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) => selection.pick();
}

class _HeldImagePicker extends images.ImagePickerPlatform {
  _HeldImagePicker(this.selection);
  final _HeldSelection selection;

  @override
  Future<List<images.XFile>> getMultiImageWithOptions({
    images.MultiImagePickerOptions options =
        const images.MultiImagePickerOptions(),
  }) => selection.pick();
}

class _UploadApi extends FakeDiscourseApi {
  _UploadApi()
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
