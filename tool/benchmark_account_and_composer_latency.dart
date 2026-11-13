import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/account_session_coordinator.dart';
import 'package:discourse_native/src/data/authenticator.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/data/private_storage.dart';
import 'package:discourse_native/src/data/secure_store.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/composer/draft_coordinator.dart';
import 'package:discourse_native/src/shell/inline_video_playback.dart';
import 'package:flutter/widgets.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

import '../test/support/fake_media_webview.dart';

const _site = 'https://forum.example';
const _apiKey = 'fixture-key';
const _credentialLatency = Duration(milliseconds: 18);
const _providerLatency = Duration(milliseconds: 20);
const _httpLatency = Duration(milliseconds: 30);
const _target = NewTopicComposerTarget(
  siteUrl: _site,
  topicTitle: 'New topic',
  draftKey: 'new_topic_12',
);
const _draftKey = 'new_topic_12';

Future<void> main() async {
  try {
    await _run();
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
  exit(0);
}

Future<void> _run() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesStorePlatform.instance =
      InMemorySharedPreferencesStore.empty();
  final directory = await Directory.systemTemp.createTemp('draft-latency-');
  try {
    stdout.writeln(
      jsonEncode({
        'disconnect_account_and_purge_drafts': await _median(
          (sample) => _disconnect(directory, sample),
        ),
        'prepare_linux_inline_video_webview': await _median((_) => _video()),
        'restore_server_composer_draft': await _median(
          (sample) => _restore(directory, sample),
        ),
      }),
    );
  } finally {
    await directory.delete(recursive: true);
  }
}

Future<int> _median(Future<int> Function(int sample) operation) async {
  final times = <int>[];
  for (var sample = 0; sample < 7; sample++) {
    final time = await operation(sample);
    if (sample >= 2) times.add(time);
  }
  times.sort();
  return times[times.length ~/ 2];
}

Future<int> _disconnect(Directory directory, int sample) async {
  final credentialStorage = _CredentialStorage();
  final lifecycle = SiteLifecycle();
  final rail = _RailPersistence();
  final host = _Host();
  final draftFile = File('${directory.path}/disconnect-$sample/drafts.json');
  final storage = ApplicationSupportDraftPersistence(file: () => draftFile);
  await storage.write('discourse_native.draft::$_site::$_draftKey', 'old text');
  final drafts = DraftStore(
    persistence: ApplicationSupportDraftPersistence(
      file: () async {
        await Future<void>.delayed(_providerLatency);
        return draftFile;
      },
    ),
  );
  var revocations = 0;
  final api = DiscourseApi(
    client: MockClient((request) async {
      if (request.url.path != '/user-api-key/revoke' ||
          request.headers['user-api-key'] != _apiKey ||
          host.instance.user != null ||
          !rail.signedOut ||
          credentialStorage.key != _apiKey) {
        throw StateError('Revocation crossed the signed-out boundary');
      }
      revocations++;
      await Future<void>.delayed(_httpLatency);
      return http.Response('{}', 200);
    }),
  );
  final coordinator = AccountSessionCoordinator(
    authenticator: Authenticator(
      store: SecureStore(storage: credentialStorage),
    ),
    instances: InstanceStore(persistence: rail),
    drafts: drafts,
    lifecycle: lifecycle,
    api: api,
    host: host,
  );
  try {
    await coordinator.authenticator.apiKeyFor(_site);
    final watch = Stopwatch()..start();
    final result = await coordinator.disconnect(_site);
    watch.stop();
    final durable = await storage.read(
      'discourse_native.draft::$_site::$_draftKey',
    );
    final accountPrefix =
        'discourse_native.account_draft::${Uri.encodeComponent(_site)}::';
    final otherAccount = await storage.read(
      '${accountPrefix}id%3A8::$_draftKey',
    );
    if (result is! AccountDisconnected ||
        !rail.signedOut ||
        rail.writes != 1 ||
        host.instance.user != null ||
        host.lastPhase != AccountSessionPhase.disconnected ||
        credentialStorage.key != null ||
        credentialStorage.reads != 1 ||
        credentialStorage.deletes != 1 ||
        revocations != 1 ||
        durable.value != null ||
        durable.allowPreferenceFallback ||
        otherAccount.allowPreferenceFallback) {
      throw StateError('Account or draft state did not settle on sign-out');
    }
    return watch.elapsedMicroseconds;
  } finally {
    api.close();
    lifecycle.close();
  }
}

Future<int> _video() async {
  final platform = _MediaPlatform();
  WebViewPlatform.instance = platform;
  final session = createInlineVideoPlaybackSession(
    InlineVideoPlaybackRequest(
      source: Uri.parse('https://cdn.example/video.mp4'),
      title: 'Video',
      posterUrl: null,
      aspectRatio: 16 / 9,
      siteUrl: null,
      credentials: null,
      lifecycle: null,
    ),
    platform: TargetPlatform.linux,
  );
  try {
    final watch = Stopwatch()..start();
    await session.start();
    watch.stop();
    final controller = platform.controller;
    if (session.state.phase != InlineVideoPlaybackPhase.ready ||
        !session.state.isBuffering ||
        controller.loaded != 1 ||
        controller.completed.length != 3 ||
        controller.delegate?.onNavigationRequest == null ||
        controller.delegate?.onPageFinished == null ||
        controller.delegate?.onWebResourceError == null) {
      throw StateError(
        'Inline video was not prepared behind its setup barrier '
        '(${session.state.phase}, ${session.state.error}, '
        'loaded ${controller.loaded}, completed ${controller.completed})',
      );
    }
    controller.delegate!.onPageFinished!('https://cdn.example/');
    if (session.state.isBuffering) throw StateError('Page finish was ignored');
    return watch.elapsedMicroseconds;
  } finally {
    session.dispose();
  }
}

final class _MediaPlatform extends WebViewPlatform {
  late final _MediaController controller;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = _MediaController(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => FakeMediaNavigationDelegate(params);
}

final class _MediaController extends PlatformWebViewController {
  _MediaController(super.params) : super.implementation();

  final completed = <String>{};
  FakeMediaNavigationDelegate? delegate;
  int loaded = 0;

  Future<void> _apply(String setting) async {
    await Future<void>.delayed(const Duration(milliseconds: 12));
    if (!completed.add(setting)) throw StateError('Duplicate setup: $setting');
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) =>
      mode == JavaScriptMode.unrestricted
      ? _apply('javascript')
      : throw StateError('Wrong JS mode');

  @override
  Future<void> setBackgroundColor(Color color) => _apply('background');

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams channel) =>
      channel.name == 'DiscourseVideo'
      ? _apply('bridge')
      : throw StateError('Wrong JS bridge');

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    delegate = handler as FakeMediaNavigationDelegate;
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    if (completed.length != 3 ||
        delegate == null ||
        baseUrl != 'https://cdn.example/' ||
        html_parser
                .parseFragment(html)
                .querySelector('video')
                ?.attributes['src'] !=
            'https://cdn.example/video.mp4') {
      throw StateError('Video loaded before complete setup');
    }
    loaded++;
  }

  @override
  Future<void> runJavaScript(String source) async {}
}

Future<int> _restore(Directory directory, int sample) async {
  final credentialStorage = _CredentialStorage();
  final lifecycle = SiteLifecycle();
  final credentials = Authenticator(
    store: SecureStore(storage: credentialStorage),
  );
  final draftFile = File('${directory.path}/restore-$sample/drafts.json');
  var requests = 0;
  var documentLookups = 0;
  const body = 'A saved message written earlier';
  final api = DiscourseApi(
    client: MockClient((request) async {
      if (request.url.path != '/drafts/$_draftKey.json' ||
          request.headers['user-api-key'] != _apiKey) {
        throw StateError('Wrong draft lookup');
      }
      requests++;
      await Future<void>.delayed(_httpLatency);
      return http.Response(
        '{"draft":{"reply":"$body","title":"Saved draft"},"draft_sequence":8}',
        200,
      );
    }),
  );
  final drafts = ComposerDraftCoordinator(
    localStore: DraftStore(
      persistence: ApplicationSupportDraftPersistence(
        file: () async {
          documentLookups++;
          await Future<void>.delayed(_providerLatency);
          return draftFile;
        },
      ),
    ),
    persistence: api,
    draftsApi: api,
    lifecycle: lifecycle,
    credentials: credentials,
    readClientId: () async => '',
    isDisposed: () => false,
    isCurrentComposer: (_) => true,
    readCachedDraft: (_) => null,
    readCachedSequence: (_) => 0,
    writeCachedDraft: (_, _, _) {},
    minimumRequiredTagsFor: (_, _) => 0,
    isServerDraftKnown: (_) => false,
    recordDraftDestroyed: (_, _, {required knownToExist}) {},
    onComposerClosed: (_) {},
  );
  final session = drafts.openSession(_target);
  final composer = ComposerController(_target, onSaveDraft: session.save);
  drafts.attach(session, composer);
  try {
    await credentials.apiKeyFor(_site);
    final watch = Stopwatch()..start();
    final restored = await drafts.finishRestore(composer);
    watch.stop();
    if (!restored ||
        composer.text.text != body ||
        composer.title.text != 'Saved draft' ||
        composer.draftSequence != 8 ||
        documentLookups < 1 ||
        documentLookups > 2 ||
        credentialStorage.reads != 1 ||
        requests != 1) {
      throw StateError('Server draft was not restored');
    }
    return watch.elapsedMicroseconds;
  } finally {
    composer.dispose();
    api.close();
    lifecycle.close();
  }
}

final class _CredentialStorage implements PrivateStorage {
  String? key = _apiKey;
  int reads = 0;
  int deletes = 0;

  @override
  Future<String?> read(String name) async {
    if (name != 'api_key::$_site') throw StateError('Unexpected read');
    reads++;
    await Future<void>.delayed(_credentialLatency);
    return key;
  }

  @override
  Future<void> delete(String name) async {
    if (name != 'api_key::$_site') throw StateError('Unexpected deletion');
    deletes++;
    key = null;
  }

  @override
  Future<void> write(String name, String value) =>
      throw StateError('Unexpected write');
}

final class _RailPersistence implements InstancePersistence {
  String? snapshot;
  int writes = 0;
  bool get signedOut {
    final row = (jsonDecode(snapshot!) as List<Object?>).single as Map;
    return row['user'] == null;
  }

  @override
  Future<String?> read() async => snapshot;

  @override
  Future<void> write(String value) async {
    writes++;
    snapshot = value;
  }
}

final class _Host implements AccountSessionHost {
  DiscourseInstance instance = const DiscourseInstance(
    url: _site,
    title: 'Forum',
    user: DiscourseUser(id: 4, username: 'sam'),
  );
  AccountSessionPhase? lastPhase;

  @override
  bool get accountSessionDisposed => false;

  @override
  List<DiscourseInstance> get accountSessionInstances => [instance];

  @override
  DiscourseInstance? accountSessionInstance(String siteUrl) =>
      instance.url == siteUrl ? instance : null;

  @override
  void clearAccountSessionState(String siteUrl) {}

  @override
  DiscourseInstance? applyAccountSessionInstance(
    DiscourseInstance replacement,
    AccountSessionPhase phase,
  ) {
    lastPhase = phase;
    return instance = replacement;
  }
}
