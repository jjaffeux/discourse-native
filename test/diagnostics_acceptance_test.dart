import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_api_client.dart';
import 'package:discourse_native/src/plugins/chat/chat_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  late DiagnosticsController diagnostics;
  late DiagnosticsSinkBinding diagnosticsBinding;

  setUp(() async {
    diagnostics = await DiagnosticsController.create(
      persistence: MemoryDiagnosticsPersistence(),
      sessionId: 'diagnostics-acceptance-session',
    );
    diagnosticsBinding = DiagnosticsSink.install(diagnostics);
  });

  tearDown(() async {
    diagnosticsBinding.close();
    await diagnostics.close();
  });

  test(
    'a topic timeout keeps the topic failure state and records its cause',
    () async {
      final credentials = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
      final shell = ShellController(
        instanceStore: FakeInstanceStore([instance('meta.example')]),
        api: _TimeoutApi(),
        authenticator: credentials,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      await pumpEventQueue();

      shell.pushContent(
        ContentRoute.topic(
          topicId: 7,
          slug: 'diagnostics-timeout',
          title: 'Diagnostics timeout',
        ),
      );
      await shell.loadTopic(7, 'diagnostics-timeout');

      expect(shell.currentTopic, isNull);
      expect(shell.currentTopicLoading, isFalse);
      _expectTimeoutEvent(
        diagnostics,
        operation: 'topic.load',
        source: 'shell',
        stackFrame: '_TimeoutApi.topic',
      );
    },
  );

  test(
    'a stalled credential read cannot leave a topic loading forever',
    () async {
      final credentials = _StalledAuthenticator();
      final api = FakeDiscourseApi(feeds: const {'/latest.json': []});
      final shell = ShellController(
        instanceStore: FakeInstanceStore([instance('meta.example')]),
        api: api,
        authenticator: credentials,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        topicLoadTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(shell.dispose);
      await shell.load();
      await pumpEventQueue();

      shell.pushContent(
        ContentRoute.topic(
          topicId: 7,
          slug: 'stalled-credentials',
          title: 'Stalled credentials',
        ),
      );
      await shell.loadTopic(7, 'stalled-credentials');

      expect(shell.currentTopic, isNull);
      expect(shell.currentTopicLoading, isFalse);
      expect(api.topicsOpened, isEmpty);
      final error = diagnostics.events
          .whereType<ErrorDiagnosticEvent>()
          .singleWhere((event) => event.operation == 'topic.load');
      expect(error.source, 'shell');
      expect(error.errorType, 'TimeoutException');
      expect(error.message, contains('reading credentials for topic 7'));
      expect(error.correlationId, isNotNull);
      expect(error.handled, isTrue);
      expect(error.degraded, isFalse);
    },
  );

  test(
    'a correlated loopback topic timeout remains diagnosable after restart',
    () async {
      diagnosticsBinding.close();
      await diagnostics.close();

      final directory = await Directory.systemTemp.createTemp(
        'discourse-native-diagnostics-acceptance-',
      );
      final historyFile = File('${directory.path}/diagnostics-v1.jsonl');
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requestReceived = Completer<HttpRequest>();
      final serverSubscription = server.listen((request) async {
        if (request.uri.path == '/t/7.json') {
          if (!requestReceived.isCompleted) requestReceived.complete(request);
          return;
        }
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'topic_list': {'topics': <Object>[]},
            }),
          );
        await request.response.close();
      });
      addTearDown(serverSubscription.cancel);

      diagnostics = await DiagnosticsController.create(
        persistence: FileDiagnosticsPersistence(historyFile),
        sessionId: 'loopback-topic-session-before-restart',
      );
      diagnosticsBinding = DiagnosticsSink.install(diagnostics);

      final ioClient = IOClient(RecordingHttpClient(HttpClient(), diagnostics));
      final api = _LoopbackTimeoutApi(ioClient);
      final siteUrl = 'http://${server.address.address}:${server.port}';
      final credentials = FakeAuthenticator()..keys[siteUrl] = 'api-key';
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          DiscourseInstance(
            url: siteUrl,
            title: 'Loopback diagnostics',
            apiVersion: 4,
          ),
        ]),
        api: api,
        authenticator: credentials,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      shell.pushContent(
        ContentRoute.topic(
          topicId: 7,
          slug: 'diagnostics-timeout',
          title: 'Diagnostics timeout',
        ),
      );

      final loading = shell.loadTopic(7, 'diagnostics-timeout');
      final heldRequest = await requestReceived.future.timeout(
        const Duration(seconds: 2),
      );
      addTearDown(() async {
        try {
          await heldRequest.response.close();
        } on Object {
          // The client intentionally aborted this socket at the deadline.
        }
      });
      expect(heldRequest.method, 'GET');
      expect(heldRequest.uri.path, '/t/7.json');
      await loading.timeout(const Duration(seconds: 2));

      expect(shell.currentTopic, isNull);
      expect(shell.currentTopicLoading, isFalse);

      final request = await _waitForTerminalRequest(
        diagnostics,
        path: '/t/7.json',
      );
      final errors = diagnostics.events
          .whereType<ErrorDiagnosticEvent>()
          .where((event) => event.operation == 'topic.load')
          .toList();
      expect(errors, hasLength(1));
      final error = errors.single;

      expect(request.state, DiagnosticHttpState.cancelled);
      expect(request.statusCode, isNull);
      expect(request.headerDuration, isNull);
      expect(request.totalDuration, isNotNull);
      expect(request.totalDuration, greaterThanOrEqualTo(api.timeout));
      expect(request.operation, 'topic.load');
      expect(request.correlationId, isNotNull);
      expect(error.source, 'shell');
      expect(error.errorType, 'TimeoutException');
      expect(error.message, contains('Future not completed'));
      expect(error.stackTrace, contains('sendBoundedHttpRequest'));
      expect(error.stackTrace, isNotEmpty);
      expect(error.operation, request.operation);
      expect(error.correlationId, request.correlationId);

      final requestEventId = request.id;
      final errorEventId = error.id;
      final correlationId = request.correlationId!;

      await diagnostics.flush();
      diagnosticsBinding.close();
      await diagnostics.close();

      diagnostics = await DiagnosticsController.create(
        persistence: FileDiagnosticsPersistence(historyFile),
        sessionId: 'loopback-topic-session-after-restart',
      );
      diagnosticsBinding = DiagnosticsSink.install(diagnostics);

      final persistedRequest = diagnostics.events
          .whereType<HttpDiagnosticEvent>()
          .singleWhere((event) => event.id == requestEventId);
      final persistedError = diagnostics.events
          .whereType<ErrorDiagnosticEvent>()
          .singleWhere((event) => event.id == errorEventId);
      expect(persistedRequest.state, DiagnosticHttpState.cancelled);
      expect(persistedRequest.operation, 'topic.load');
      expect(persistedRequest.correlationId, correlationId);
      expect(persistedError.errorType, 'TimeoutException');
      expect(persistedError.message, contains('Future not completed'));
      expect(persistedError.stackTrace, contains('sendBoundedHttpRequest'));
      expect(persistedError.operation, persistedRequest.operation);
      expect(persistedError.correlationId, correlationId);
    },
  );

  test(
    'a channel timeout keeps the channel failure state and records its cause',
    () async {
      final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'api-key';
      final chat = ChatController(
        api: _TimeoutApi(),
        credentials: credentials,
        store: Store(),
        reporter: PluginDiagnosticsReporter.fixed(diagnostics),
      );
      addTearDown(chat.dispose);

      await chat.openChannel(_siteUrl, 9);

      final stream = chat.stream(_siteUrl, 9);
      expect(stream.loading, isFalse);
      expect(stream.fetchedOnce, isTrue);
      expect(stream.messageIds, isEmpty);
      expect(stream.error, 'Could not load this channel.');
      _expectTimeoutEvent(
        diagnostics,
        operation: 'chat.loadWindow',
        source: 'chat',
        stackFrame: '_TimeoutApi.chatMessages',
      );
    },
  );

  test(
    'a correlated loopback channel timeout remains diagnosable after restart',
    () async {
      diagnosticsBinding.close();
      await diagnostics.close();

      final directory = await Directory.systemTemp.createTemp(
        'discourse-native-chat-diagnostics-acceptance-',
      );
      final historyFile = File('${directory.path}/diagnostics-v1.jsonl');
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requestReceived = Completer<HttpRequest>();
      final serverSubscription = server.listen((request) {
        if (!requestReceived.isCompleted) requestReceived.complete(request);
      });
      addTearDown(serverSubscription.cancel);

      diagnostics = await DiagnosticsController.create(
        persistence: FileDiagnosticsPersistence(historyFile),
        sessionId: 'loopback-chat-session-before-restart',
      );
      diagnosticsBinding = DiagnosticsSink.install(diagnostics);

      final ioClient = IOClient(RecordingHttpClient(HttpClient(), diagnostics));
      final api = _LoopbackTimeoutApi(ioClient);
      final siteUrl = 'http://${server.address.address}:${server.port}';
      final credentials = FakeApiCredentialReader()..keys[siteUrl] = 'api-key';
      final chat = ChatController(
        api: ChatApiClient(api),
        credentials: credentials,
        store: Store(),
        reporter: PluginDiagnosticsReporter.fixed(diagnostics),
      );
      addTearDown(chat.dispose);

      final opening = chat.openChannel(siteUrl, 9);
      final heldRequest = await requestReceived.future.timeout(
        const Duration(seconds: 2),
      );
      addTearDown(() async {
        try {
          await heldRequest.response.close();
        } on Object {
          // The client intentionally aborted this socket at the deadline.
        }
      });
      expect(heldRequest.method, 'GET');
      expect(heldRequest.uri.path, '/chat/api/channels/9/messages.json');
      expect(heldRequest.uri.queryParameters['page_size'], '50');
      expect(heldRequest.uri.queryParameters['fetch_from_last_read'], 'true');
      await opening.timeout(const Duration(seconds: 2));

      final stream = chat.stream(siteUrl, 9);
      expect(stream.loading, isFalse);
      expect(stream.fetchedOnce, isTrue);
      expect(stream.messageIds, isEmpty);
      expect(stream.error, 'Could not load this channel.');

      final request = await _waitForTerminalRequest(
        diagnostics,
        path: '/chat/api/channels/9/messages.json',
      );
      final errors = diagnostics.events
          .whereType<ErrorDiagnosticEvent>()
          .where((event) => event.operation == 'chat.loadWindow')
          .toList();
      expect(errors, hasLength(1));
      final error = errors.single;

      expect(request.state, DiagnosticHttpState.cancelled);
      expect(request.statusCode, isNull);
      expect(request.headerDuration, isNull);
      expect(request.totalDuration, isNotNull);
      expect(request.totalDuration, greaterThanOrEqualTo(api.timeout));
      expect(request.operation, 'chat.loadWindow');
      expect(request.correlationId, isNotNull);
      expect(error.source, 'chat');
      expect(error.errorType, 'TimeoutException');
      expect(error.message, contains('Future not completed'));
      expect(error.stackTrace, contains('sendBoundedHttpRequest'));
      expect(error.stackTrace, isNotEmpty);
      expect(error.operation, request.operation);
      expect(error.correlationId, request.correlationId);
      expect(error.handled, isTrue);
      expect(error.degraded, isFalse);

      final requestEventId = request.id;
      final errorEventId = error.id;
      final correlationId = request.correlationId!;

      await diagnostics.flush();
      diagnosticsBinding.close();
      await diagnostics.close();

      diagnostics = await DiagnosticsController.create(
        persistence: FileDiagnosticsPersistence(historyFile),
        sessionId: 'loopback-chat-session-after-restart',
      );
      diagnosticsBinding = DiagnosticsSink.install(diagnostics);

      final persistedRequest = diagnostics.events
          .whereType<HttpDiagnosticEvent>()
          .singleWhere((event) => event.id == requestEventId);
      final persistedError = diagnostics.events
          .whereType<ErrorDiagnosticEvent>()
          .singleWhere((event) => event.id == errorEventId);
      expect(persistedRequest.state, DiagnosticHttpState.cancelled);
      expect(persistedRequest.operation, 'chat.loadWindow');
      expect(persistedRequest.correlationId, correlationId);
      expect(persistedError.errorType, 'TimeoutException');
      expect(persistedError.message, contains('Future not completed'));
      expect(persistedError.stackTrace, contains('sendBoundedHttpRequest'));
      expect(persistedError.operation, persistedRequest.operation);
      expect(persistedError.correlationId, correlationId);
    },
  );

  test(
    'a disposed channel request is excluded from operational errors',
    () async {
      final api = _GatedTimeoutApi();
      final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'api-key';
      final chat = ChatController(
        api: api,
        credentials: credentials,
        store: Store(),
      );

      final opening = chat.openChannel(_siteUrl, 9);
      await api.started.future;
      chat.dispose();
      api.release.complete();
      await opening;

      expect(
        diagnostics.events.whereType<ErrorDiagnosticEvent>().where(
          (event) => event.operation == 'chat.loadWindow',
        ),
        isEmpty,
      );
    },
  );

  test(
    'a channel failure from an invalidated site session is excluded',
    () async {
      final api = _GatedTimeoutApi();
      final lifecycle = SiteLifecycle();
      final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'api-key';
      final chat = ChatController(
        api: api,
        credentials: credentials,
        store: Store(),
        lifecycle: lifecycle,
      );
      addTearDown(chat.dispose);

      final opening = chat.openChannel(_siteUrl, 9);
      await api.started.future;
      lifecycle.invalidate(_siteUrl);
      chat.forget(_siteUrl);
      api.release.complete();
      await opening;

      expect(
        diagnostics.events.whereType<ErrorDiagnosticEvent>().where(
          (event) => event.operation == 'chat.loadWindow',
        ),
        isEmpty,
      );
    },
  );

  test(
    'a topic failure from an invalidated site session is excluded',
    () async {
      final api = _GatedTopicTimeoutApi();
      final credentials = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
      final shell = ShellController(
        instanceStore: FakeInstanceStore([instance('meta.example')]),
        api: api,
        authenticator: credentials,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      await pumpEventQueue();

      shell.pushContent(
        ContentRoute.topic(
          topicId: 7,
          slug: 'diagnostics-timeout',
          title: 'Diagnostics timeout',
        ),
      );
      final loading = shell.loadTopic(7, 'diagnostics-timeout');
      await api.started.future;
      shell.lifecycle.invalidate(_siteUrl);
      api.release.complete();
      await loading;

      expect(
        diagnostics.events.whereType<ErrorDiagnosticEvent>().where(
          (event) => event.operation == 'topic.load',
        ),
        isEmpty,
      );
    },
  );
}

void _expectTimeoutEvent(
  DiagnosticsController diagnostics, {
  required String operation,
  required String source,
  required String stackFrame,
}) {
  final event = diagnostics.events
      .whereType<ErrorDiagnosticEvent>()
      .singleWhere((candidate) => candidate.operation == operation);

  expect(event.source, source);
  expect(event.errorType, 'TimeoutException');
  expect(event.message, contains('forced diagnostics timeout'));
  expect(event.stackTrace, contains(stackFrame));
  expect(event.stackTrace, isNotEmpty);
  expect(event.correlationId, isNotNull);
  expect(event.handled, isTrue);
  expect(event.degraded, isFalse);
}

Future<HttpDiagnosticEvent> _waitForTerminalRequest(
  DiagnosticsController diagnostics, {
  required String path,
}) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    final candidates = diagnostics.events
        .whereType<HttpDiagnosticEvent>()
        .where((event) => event.uri.contains(path));
    if (candidates.isNotEmpty) {
      final event = candidates.single;
      if (event.state != DiagnosticHttpState.pending) return event;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('The loopback request for $path never became terminal.');
}

class _TimeoutApi extends FakeDiscourseApi {
  _TimeoutApi() : super(feeds: const {'/latest.json': []});

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
  }) async {
    throw TimeoutException('forced diagnostics timeout while loading topic');
  }

  @override
  Future<ChatMessagePage> chatMessages({
    required String siteUrl,
    required int channelId,
    int? before,
    int? after,
    int? targetMessageId,
    bool fromLastRead = false,
    int pageSize = 50,
    String? apiKey,
    String? clientId,
  }) async {
    throw TimeoutException('forced diagnostics timeout while loading channel');
  }
}

final class _StalledAuthenticator extends FakeAuthenticator {
  @override
  Future<String?> apiKeyFor(String siteUrl) => Completer<String?>().future;
}

final class _GatedTimeoutApi extends _TimeoutApi {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<ChatMessagePage> chatMessages({
    required String siteUrl,
    required int channelId,
    int? before,
    int? after,
    int? targetMessageId,
    bool fromLastRead = false,
    int pageSize = 50,
    String? apiKey,
    String? clientId,
  }) async {
    started.complete();
    await release.future;
    return super.chatMessages(
      siteUrl: siteUrl,
      channelId: channelId,
      before: before,
      after: after,
      targetMessageId: targetMessageId,
      fromLastRead: fromLastRead,
      pageSize: pageSize,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}

final class _GatedTopicTimeoutApi extends _TimeoutApi {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
  }) async {
    started.complete();
    await release.future;
    return super.topic(
      siteUrl: siteUrl,
      slug: slug,
      id: id,
      postNumber: postNumber,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}

final class _LoopbackTimeoutApi extends DiscourseApi {
  _LoopbackTimeoutApi(http.Client client)
    : super(client: client, timeout: const Duration(milliseconds: 50));

  @override
  Future<SiteConfig> siteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async => const SiteConfig.unknown();

  @override
  Future<Map<String, String>> customEmojis({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async => const {};

  @override
  Future<List<TopicCategory>> categories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async => const [];

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async => CategoryLoadResult(const []);
}
