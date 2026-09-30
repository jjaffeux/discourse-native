import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart'
    show DButton, DDropdownMenuCheckboxItem, DToaster;
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_generation_write.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_proofreading_api.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_proofreading_controller.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_proofreading_data.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_proofreading_plugin.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_proofreading_preferences.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _readerId = 7;
const _proofreadingNotice = 'Unable to proofread. Posting as written.';

SiteConfig _configWith({
  bool allowedInPrivateMessages = false,
  bool contextMenuEnabled = true,
}) => SiteConfig(
  plugins: PluginData.none.withValue(
    discourseAiSettingsDataKey,
    DiscourseAiSettings(
      enabled: true,
      helperEnabled: true,
      helperAllowedInPrivateMessages: allowedInPrivateMessages,
      helperContextMenuEnabled: contextMenuEnabled,
    ),
  ),
);

final _enabledConfig = _configWith();

DiscourseUser _userWith({bool canProofread = true}) => DiscourseUser(
  id: _readerId,
  username: 'reader',
  plugins: PluginData.none.withValue(
    discourseAiCurrentUserDataKey,
    DiscourseAiCurrentUser(canUseAssistant: true, canProofread: canProofread),
  ),
);

final _allowedUser = _userWith();

const _replyTarget = ComposerTarget(
  siteUrl: _siteUrl,
  topicId: 7,
  slug: 'native-writing',
  topicTitle: 'Native writing',
);

const _newTopicTarget = ComposerTarget(
  siteUrl: _siteUrl,
  topicId: 0,
  slug: '',
  topicTitle: 'New topic',
  mode: ComposerMode.newTopic,
);

const _messageTarget = ComposerTarget(
  siteUrl: _siteUrl,
  topicId: 0,
  slug: '',
  topicTitle: 'New message',
  mode: ComposerMode.privateMessage,
  targetRecipients: 'sam',
);

const _messageReplyTarget = ComposerTarget(
  siteUrl: _siteUrl,
  topicId: 8,
  slug: 'a-message',
  topicTitle: 'A message',
  privateMessageTopic: true,
);

const _userWithoutAssistant = DiscourseUser(id: _readerId, username: 'reader');

final class _FailingCredentialReader extends FakeApiCredentialReader {
  @override
  Future<String?> apiKeyFor(String siteUrl) async =>
      throw StateError('Credential storage unavailable');
}

final class _FreshAccountHost implements PluginFreshAccountHost {
  _FreshAccountHost(this.data);

  PluginData data;

  @override
  PluginFreshAccountProfile? profileFor(String siteUrl) => null;

  @override
  T? recordFor<T extends Object>(String siteUrl, PluginDataKey<T> key) =>
      data.get(key);
}

final class _GatedProofreadingTransport extends FakeDiscourseApi {
  _GatedProofreadingTransport(this.proofreadingGate)
    : super(
        pluginResponses: const {
          'POST $aiProofreadingPath': {
            'suggestions': ['The delayed suggestion.'],
          },
        },
      );

  final Completer<void> proofreadingGate;
  final Completer<void> started = Completer<void>();

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    if (!started.isCompleted) started.complete();
    await proofreadingGate.future;
    return super.pluginWriteJson(
      siteUrl: siteUrl,
      path: path,
      method: method,
      apiKey: apiKey,
      body: body,
      clientId: clientId,
    );
  }
}

/// The production transport against a site whose one request is answered
/// only when the test says so, so the deadline it applies is the real one.
final class _HeldSite {
  _HeldSite() {
    api = DiscourseApi(
      client: MockClient((request) {
        requests.add(request);
        return _reply.future;
      }),
    );
    addTearDown(api.close);
  }

  late final DiscourseApi api;
  final requests = <http.Request>[];
  final _reply = Completer<http.Response>();

  void reply(Map<String, Object?> body) => _reply.complete(
    http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    ),
  );
}

AiProofreadingController _controller({
  SiteConfig? config,
  DiscourseUser? user,
  PluginApiTransport? api,
  SiteLifecycle? lifecycle,
  _FreshAccountHost? freshAccount,
  PluginUserIdReader? currentUserId,
  FakeApiCredentialReader? credentials,
  AiProofreadingPreferenceStore preferences =
      const AiProofreadingPreferenceStore(),
}) {
  return AiProofreadingController(
    api: AiProofreadingApi(
      api ??
          FakeDiscourseApi(
            pluginResponses: const {
              'POST $aiProofreadingPath': {
                'suggestions': ['A polished reply.'],
              },
            },
          ),
    ),
    requests: FakePluginRequestHost(
      credentials:
          credentials ??
          (FakeApiCredentialReader()..keys[_siteUrl] = 'api-key'),
      lifecycle: lifecycle,
    ),
    siteState: PluginSiteStateHost(
      currentUserFor: (_) => user,
      siteConfigFor: (_) => config ?? _enabledConfig,
    ),
    freshAccount:
        freshAccount ?? _FreshAccountHost((user ?? _allowedUser).plugins),
    currentUserId: currentUserId ?? (_) => (user ?? _allowedUser).id,
    preferences: preferences,
  );
}

Future<({ShellController shell, FakeDiscourseApi api})> _openReply({
  Map<String, dynamic>? proofreadingResponse = const {
    'suggestions': ['This is the polished reply.'],
  },
  WriteException? proofreadingFailure,
  WriteException? postingFailure,
  SiteConfig? config,
  bool privateMessage = false,
}) async {
  final api = FakeDiscourseApi(
    writeFailure: postingFailure,
    user: _allowedUser,
    feeds: const {'/latest.json': <Topic>[]},
    topics: {
      7: topicPayload(
        id: 7,
        title: 'Native writing',
        canCreatePost: true,
        privateMessage: privateMessage,
      ),
    },
    siteConfigs: {_siteUrl: config ?? _enabledConfig},
    pluginResponses: proofreadingResponse == null
        ? const {}
        : {'POST $aiProofreadingPath': proofreadingResponse},
    pluginWriteFailures: proofreadingFailure == null
        ? null
        : {'POST $aiProofreadingPath': proofreadingFailure},
  );
  final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _allowedUser),
    ]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: PluginInstaller.install(bundledPluginManifest),
  );
  await shell.load();
  shell.pushContent(
    ContentRoute.topic(
      topicId: 7,
      slug: 'native-writing',
      title: 'Native writing',
    ),
  );
  await shell.loadTopic(7, 'native-writing');
  shell.openReply();
  return (shell: shell, api: api);
}

Future<void> _pumpComposer(
  WidgetTester tester,
  ShellController shell, {
  ComposerController? composer,
  bool minimized = false,
  bool submissionFeedback = false,
}) {
  final panel = ComposerPanel(
    composer: composer ?? shell.visibleComposer!,
    minimized: minimized,
    height: minimized ? null : 500,
  );
  if (submissionFeedback) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      builder: submissionFeedback
          ? (context, child) => DToaster(child: child!)
          : null,
      home: ShellScope(
        controller: shell,
        child: Scaffold(
          body: submissionFeedback
              ? ListenableBuilder(
                  listenable: shell,
                  builder: (context, _) => shell.visibleComposer == null
                      ? const SizedBox.shrink()
                      : panel,
                )
              : panel,
        ),
      ),
    ),
  );
}

Future<void> _openOptions(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('composer-options')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('composer-options')));
  await tester.pumpAndSettle();
}

void main() {
  test('decodes the AI settings and assistant permission conservatively', () {
    const plugin = AiProofreadingPlugin();

    expect(
      plugin.readSiteSettings(const {
        'discourse_ai_enabled': true,
        'ai_helper_enabled': true,
        'ai_helper_allowed_in_pm': true,
        'ai_helper_enabled_features': 'suggestions|context_menu',
      }, _siteUrl),
      const DiscourseAiSettings(
        enabled: true,
        helperEnabled: true,
        helperAllowedInPrivateMessages: true,
        helperContextMenuEnabled: true,
      ),
    );
    for (final features in [
      null,
      '',
      'suggestions',
      const ['suggestions'],
    ]) {
      final settings = plugin.readSiteSettings({
        'discourse_ai_enabled': true,
        'ai_helper_enabled': true,
        'ai_helper_enabled_features': features,
      }, _siteUrl);

      expect(settings.helperAllowedInPrivateMessages, isFalse);
      expect(settings.helperContextMenuEnabled, isFalse, reason: '$features');
      expect(settings.proofreadingAvailable, isFalse);
    }
    expect(plugin.readCurrentUser(const {}, _siteUrl), isNull);
    expect(
      plugin.readCurrentUser(const {
        'can_use_assistant': true,
        'ai_helper_prompts': [
          {'name': 'translate'},
          {'name': 'proofread'},
        ],
      }, _siteUrl),
      const DiscourseAiCurrentUser(canUseAssistant: true, canProofread: true),
    );
    for (final prompts in [
      null,
      'proofread',
      const ['proofread'],
      const [
        {'name': 'translate'},
      ],
    ]) {
      expect(
        plugin.readCurrentUser({
          'can_use_assistant': true,
          'ai_helper_prompts': prompts,
        }, _siteUrl),
        const DiscourseAiCurrentUser(
          canUseAssistant: true,
          canProofread: false,
        ),
        reason: '$prompts',
      );
    }
  });

  test('stored AI records keep every gate and read older ones as closed', () {
    const plugin = AiProofreadingPlugin();
    const settings = DiscourseAiSettings(
      enabled: true,
      helperEnabled: true,
      helperAllowedInPrivateMessages: true,
      helperContextMenuEnabled: true,
    );
    const user = DiscourseAiCurrentUser(
      canUseAssistant: true,
      canProofread: true,
    );
    Object? stored(Object? value) => jsonDecode(jsonEncode(value));

    expect(
      plugin.siteSettingsCodec.decode(
        stored(plugin.siteSettingsCodec.encode(settings)),
      ),
      settings,
    );
    expect(
      plugin.currentUserCodec.decode(
        stored(plugin.currentUserCodec.encode(user)),
      ),
      user,
    );
    expect(
      plugin.siteSettingsCodec.decode(
        stored({'enabled': true, 'helperEnabled': true}),
      ),
      const DiscourseAiSettings(
        enabled: true,
        helperEnabled: true,
        helperAllowedInPrivateMessages: false,
        helperContextMenuEnabled: false,
      ),
    );
    expect(
      plugin.currentUserCodec.decode(stored({'canUseAssistant': true})),
      const DiscourseAiCurrentUser(canUseAssistant: true, canProofread: false),
    );
  });

  test('is available for new topics and public replies only', () {
    final controller = _controller();
    addTearDown(controller.dispose);
    final reply = ComposerController(_replyTarget);
    final newTopic = ComposerController(_newTopicTarget);
    final message = ComposerController(_messageTarget);
    final messageReply = ComposerController(_messageReplyTarget);
    final edit = ComposerController(
      const ComposerTarget(
        siteUrl: _siteUrl,
        topicId: 7,
        slug: 'native-writing',
        topicTitle: 'Native writing',
        editingPostId: 11,
        editingPostNumber: 2,
      ),
    );
    addTearDown(reply.dispose);
    addTearDown(newTopic.dispose);
    addTearDown(message.dispose);
    addTearDown(messageReply.dispose);
    addTearDown(edit.dispose);

    expect(controller.isAvailable(reply), isTrue);
    expect(controller.isAvailable(newTopic), isTrue);
    expect(controller.isAvailable(message), isFalse);
    expect(controller.isAvailable(messageReply), isFalse);
    expect(controller.isAvailable(edit), isFalse);
  });

  test('stays hidden without both AI settings and user permission', () {
    final disabled = _controller(config: const SiteConfig.unknown());
    final disallowed = _controller(user: _userWithoutAssistant);
    final withoutComposerHelper = _controller(
      config: _configWith(contextMenuEnabled: false),
    );
    final outsideProofreaderGroups = _controller(
      user: _userWith(canProofread: false),
    );
    final composer = ComposerController(_replyTarget);
    addTearDown(disabled.dispose);
    addTearDown(disallowed.dispose);
    addTearDown(withoutComposerHelper.dispose);
    addTearDown(outsideProofreaderGroups.dispose);
    addTearDown(composer.dispose);

    expect(disabled.isAvailable(composer), isFalse);
    expect(disallowed.isAvailable(composer), isFalse);
    expect(withoutComposerHelper.isAvailable(composer), isFalse);
    expect(outsideProofreaderGroups.isAvailable(composer), isFalse);
  });

  test(
    'a remembered choice never sends a message reply to the helper',
    () async {
      final api = FakeDiscourseApi(
        pluginResponses: const {
          'POST $aiProofreadingPath': {
            'suggestions': ['A polished private reply.'],
          },
        },
      );
      final controller = _controller(api: api);
      final reply = ComposerController(_replyTarget);
      final messageReply = ComposerController(_messageReplyTarget);
      addTearDown(controller.dispose);
      addTearDown(reply.dispose);
      addTearDown(messageReply.dispose);
      controller.setEnabled(reply, true);
      messageReply.text.text = 'a private reply with typo';

      final result = await controller.prepareComposerSubmit(messageReply);

      expect(result.failure, isNull);
      expect(result.changed, isFalse);
      expect(messageReply.raw, 'a private reply with typo');
      expect(api.pluginWrites, isEmpty);
      expect(controller.isEnabled(reply), isTrue);
    },
  );

  test('a message reply is proofread where the site allows it', () async {
    final api = FakeDiscourseApi(
      pluginResponses: const {
        'POST $aiProofreadingPath': {
          'suggestions': ['A polished private reply.'],
        },
      },
    );
    final controller = _controller(
      api: api,
      config: _configWith(allowedInPrivateMessages: true),
    );
    final messageReply = ComposerController(_messageReplyTarget);
    addTearDown(controller.dispose);
    addTearDown(messageReply.dispose);
    messageReply.text.text = 'a private reply with typo';

    expect(controller.isAvailable(messageReply), isTrue);
    controller.setEnabled(messageReply, true);
    final result = await controller.prepareComposerSubmit(messageReply);

    expect(result.failure, isNull);
    expect(result.changed, isTrue);
    expect(messageReply.raw, 'A polished private reply.');
    expect(api.pluginWrites.single.path, aiProofreadingPath);
  });

  test('remembers the choice independently for each account', () async {
    const store = AiProofreadingPreferenceStore();

    expect(await store.read(siteUrl: _siteUrl, userId: _readerId), isFalse);

    await store.write(siteUrl: _siteUrl, userId: _readerId, enabled: true);

    expect(await store.read(siteUrl: _siteUrl, userId: _readerId), isTrue);
    expect(await store.read(siteUrl: _siteUrl, userId: 8), isFalse);
    expect(
      await store.read(
        siteUrl: 'https://other.discourse.org',
        userId: _readerId,
      ),
      isFalse,
    );
  });

  for (final nextCanProofread in [true, false]) {
    test('another account on the forum does not inherit the choice '
        '(${nextCanProofread ? 'can' : 'cannot'} proofread)', () async {
      var userId = 1;
      final account = _FreshAccountHost(_allowedUser.plugins);
      final api = FakeDiscourseApi(
        pluginResponses: const {
          'POST $aiProofreadingPath': {
            'suggestions': ['A polished reply.'],
          },
        },
      );
      final controller = _controller(
        api: api,
        freshAccount: account,
        currentUserId: (_) => userId,
      );
      final chosen = ComposerController(_replyTarget);
      final next = ComposerController(_replyTarget);
      final returned = ComposerController(_replyTarget);
      addTearDown(controller.dispose);
      addTearDown(chosen.dispose);
      addTearDown(next.dispose);
      addTearDown(returned.dispose);
      controller.setEnabled(chosen, true);

      userId = 2;
      account.data = _userWith(canProofread: nextCanProofread).plugins;
      controller.forget(_siteUrl);
      next.text.text = 'a reply with typo';

      expect(controller.isEnabled(next), isFalse);
      final result = await controller.prepareComposerSubmit(next);

      expect(result.failure, isNull);
      expect(result.changed, isFalse);
      expect(next.raw, 'a reply with typo');
      expect(api.pluginWrites, isEmpty);
      expect(controller.isEnabled(next), isFalse);

      userId = 1;
      account.data = _allowedUser.plugins;
      controller.forget(_siteUrl);
      returned.text.text = 'a reply with typo';
      final restored = await controller.prepareComposerSubmit(returned);

      expect(controller.isEnabled(returned), isTrue);
      expect(restored.changed, isTrue);
      expect(returned.raw, 'A polished reply.');
      expect(api.pluginWrites.single.path, aiProofreadingPath);
    });
  }

  test('a choice stored for the whole forum is removed, not adopted', () async {
    final siteWideKey =
        'discourse_native.ai_proofreading_enabled.'
        '${Uri.encodeComponent(_siteUrl)}';
    SharedPreferences.setMockInitialValues({siteWideKey: true});
    final api = FakeDiscourseApi(
      pluginResponses: const {
        'POST $aiProofreadingPath': {
          'suggestions': ['A polished reply.'],
        },
      },
    );
    final controller = _controller(api: api);
    final composer = ComposerController(_replyTarget);
    addTearDown(controller.dispose);
    addTearDown(composer.dispose);
    composer.text.text = 'a reply with typo';

    final result = await controller.prepareComposerSubmit(composer);

    expect(result.failure, isNull);
    expect(result.changed, isFalse);
    expect(api.pluginWrites, isEmpty);
    expect(controller.isEnabled(composer), isFalse);
    expect(
      (await SharedPreferences.getInstance()).containsKey(siteWideKey),
      isFalse,
    );
  });

  test(
    'proofreads the unchanged body with the supported server contract',
    () async {
      final api = FakeDiscourseApi(
        pluginResponses: const {
          'POST $aiProofreadingPath': {
            'suggestions': ['A polished reply.'],
          },
        },
      );
      final controller = _controller(api: api);
      final composer = ComposerController(_replyTarget);
      addTearDown(controller.dispose);
      addTearDown(composer.dispose);
      composer.text.text = 'a reply with typo';
      controller.setEnabled(composer, true);

      final result = await controller.prepareComposerSubmit(composer);

      expect(result.failure, isNull);
      expect(result.changed, isTrue);
      expect(result.notice, isNull);
      expect(composer.raw, 'A polished reply.');
      expect(api.pluginWrites.single.path, aiProofreadingPath);
      expect(api.pluginWrites.single.body, {
        'text': 'a reply with typo',
        'mode': 'proofread',
      });
    },
  );

  testWidgets('a proofread slower than an ordinary write is still applied', (
    tester,
  ) async {
    final site = _HeldSite();
    final controller = _controller(api: site.api);
    final composer = ComposerController(_replyTarget);
    addTearDown(controller.dispose);
    addTearDown(composer.dispose);
    composer.text.text = 'a long reply with typo';
    controller.setEnabled(composer, true);

    PluginComposerSubmitPreparation? result;
    unawaited(
      controller.prepareComposerSubmit(composer).then((value) {
        result = value;
      }),
    );
    await tester.pump();
    expect(site.requests.single.url.path, aiProofreadingPath);
    await tester.pump(const Duration(seconds: 30));
    expect(result, isNull);

    site.reply({
      'suggestions': ['A polished long reply.'],
    });
    await tester.pump();

    expect(result?.failure, isNull);
    expect(result?.changed, isTrue);
    expect(result?.notice, isNull);
    expect(composer.raw, 'A polished long reply.');
  });

  for (final throwsError in [false, true]) {
    test('proofreading credential ${throwsError ? 'error' : 'failure'} '
        'continues with a notice', () async {
      final api = FakeDiscourseApi();
      final controller = _controller(
        api: api,
        credentials: throwsError
            ? _FailingCredentialReader()
            : FakeApiCredentialReader(),
      );
      final composer = ComposerController(_replyTarget);
      addTearDown(controller.dispose);
      addTearDown(composer.dispose);
      composer.text.text = 'The original reply.';
      controller.setEnabled(composer, true);

      final result = await controller.prepareComposerSubmit(composer);

      expect(result.failure, isNull);
      expect(result.changed, isFalse);
      expect(result.notice, _proofreadingNotice);
      expect(composer.raw, 'The original reply.');
      expect(api.pluginWrites, isEmpty);
    });
  }

  test('a successful proofread with no changes has no warning', () async {
    final controller = _controller();
    final composer = ComposerController(_replyTarget);
    addTearDown(controller.dispose);
    addTearDown(composer.dispose);
    composer.text.text = 'A polished reply.';
    controller.setEnabled(composer, true);

    final result = await controller.prepareComposerSubmit(composer);

    expect(result.failure, isNull);
    expect(result.changed, isFalse);
    expect(result.notice, isNull);
    expect(composer.raw, 'A polished reply.');
  });

  testWidgets('a proofread past its deadline posts what was written', (
    tester,
  ) async {
    final site = _HeldSite();
    final controller = _controller(api: site.api);
    final composer = ComposerController(_replyTarget);
    addTearDown(controller.dispose);
    addTearDown(composer.dispose);
    composer.text.text = 'a long reply with typo';
    controller.setEnabled(composer, true);

    PluginComposerSubmitPreparation? result;
    unawaited(
      controller.prepareComposerSubmit(composer).then((value) {
        result = value;
      }),
    );
    await tester.pump();
    await tester.pump(aiGenerationTimeout - const Duration(seconds: 1));
    expect(result, isNull);

    await tester.pump(const Duration(seconds: 1));

    expect(result?.failure, isNull);
    expect(result?.changed, isFalse);
    expect(result?.notice, _proofreadingNotice);
    expect(composer.raw, 'a long reply with typo');
    expect(controller.isEnabled(composer), isTrue);
  });

  test('does not overwrite a body changed during proofreading', () async {
    final gate = Completer<void>();
    final api = _GatedProofreadingTransport(gate);
    final controller = _controller(api: api);
    final composer = ComposerController(_replyTarget);
    addTearDown(controller.dispose);
    addTearDown(composer.dispose);
    composer.text.text = 'The original reply.';
    controller.setEnabled(composer, true);

    final preparation = controller.prepareComposerSubmit(composer);
    await api.started.future;
    composer.text.text = 'The author kept typing.';
    gate.complete();
    final result = await preparation;

    expect(result.failure, isNull);
    expect(result.changed, isFalse);
    expect(result.notice, _proofreadingNotice);
    expect(composer.raw, 'The author kept typing.');
  });

  test(
    'does not proceed after a failed request from an expired session',
    () async {
      final gate = Completer<void>();
      final api = _GatedProofreadingTransport(gate)
        ..pluginWriteFailures['POST $aiProofreadingPath'] =
            const WriteException(WriteFailure.unreachable, statusCode: 500);
      final lifecycle = SiteLifecycle();
      final controller = _controller(api: api, lifecycle: lifecycle);
      final composer = ComposerController(_replyTarget);
      addTearDown(controller.dispose);
      addTearDown(composer.dispose);
      composer.text.text = 'The original reply.';
      controller.setEnabled(composer, true);

      final preparation = controller.prepareComposerSubmit(composer);
      await api.started.future;
      lifecycle.invalidate(_siteUrl);
      gate.complete();
      final result = await preparation;

      expect(result.failure?.failure, WriteFailure.conflict);
      expect(composer.raw, 'The original reply.');
    },
  );

  test('a remembered choice never holds up a private message', () async {
    final api = FakeDiscourseApi(
      pluginResponses: const {
        'POST $aiProofreadingPath': {
          'suggestions': ['A polished message.'],
        },
      },
    );
    final controller = _controller(api: api);
    final reply = ComposerController(_replyTarget);
    final message = ComposerController(_messageTarget);
    addTearDown(controller.dispose);
    addTearDown(reply.dispose);
    addTearDown(message.dispose);
    controller.setEnabled(reply, true);
    message.text.text = 'a message with typo';

    final result = await controller.prepareComposerSubmit(message);

    expect(result.failure, isNull);
    expect(result.changed, isFalse);
    expect(message.raw, 'a message with typo');
    expect(api.pluginWrites, isEmpty);
    expect(controller.isEnabled(reply), isTrue);
  });

  test(
    'unavailable proofreading lets the first submit and retries post',
    () async {
      const store = AiProofreadingPreferenceStore();
      await store.write(siteUrl: _siteUrl, userId: _readerId, enabled: true);
      final api = FakeDiscourseApi();
      final controller = _controller(api: api, user: _userWithoutAssistant);
      final composer = ComposerController(_replyTarget);
      addTearDown(controller.dispose);
      addTearDown(composer.dispose);
      composer.text.text = 'a reply with typo';

      final first = await controller.prepareComposerSubmit(composer);

      expect(first.failure, isNull);
      expect(first.changed, isFalse);
      expect(first.notice, _proofreadingNotice);
      for (var retry = 0; retry < 2; retry++) {
        final result = await controller.prepareComposerSubmit(composer);

        expect(result.failure, isNull);
        expect(result.changed, isFalse);
        expect(result.notice, isNull);
      }
      expect(composer.raw, 'a reply with typo');
      expect(api.pluginWrites, isEmpty);
      expect(await store.read(siteUrl: _siteUrl, userId: _readerId), isTrue);
    },
  );

  test('unavailable proofreading is reported per composer', () async {
    await const AiProofreadingPreferenceStore().write(
      siteUrl: _siteUrl,
      userId: _readerId,
      enabled: true,
    );
    final controller = _controller(user: _userWithoutAssistant);
    final told = ComposerController(_replyTarget);
    final next = ComposerController(_newTopicTarget);
    addTearDown(controller.dispose);
    addTearDown(told.dispose);
    addTearDown(next.dispose);

    final first = await controller.prepareComposerSubmit(told);
    final retry = await controller.prepareComposerSubmit(told);
    final other = await controller.prepareComposerSubmit(next);

    expect(first.failure, isNull);
    expect(first.notice, _proofreadingNotice);
    expect(retry.failure, isNull);
    expect(retry.notice, isNull);
    expect(other.failure, isNull);
    expect(other.notice, _proofreadingNotice);
  });

  test(
    'a composer that posts without proofreading keeps that until re-enabled',
    () async {
      await const AiProofreadingPreferenceStore().write(
        siteUrl: _siteUrl,
        userId: _readerId,
        enabled: true,
      );
      final account = _FreshAccountHost(PluginData.none);
      final api = FakeDiscourseApi(
        pluginResponses: const {
          'POST $aiProofreadingPath': {
            'suggestions': ['A polished reply.'],
          },
        },
      );
      final controller = _controller(api: api, freshAccount: account);
      final composer = ComposerController(_replyTarget);
      final later = ComposerController(_replyTarget);
      addTearDown(controller.dispose);
      addTearDown(composer.dispose);
      addTearDown(later.dispose);
      composer.text.text = 'a reply with typo';

      final first = await controller.prepareComposerSubmit(composer);
      account.data = _allowedUser.plugins;
      final retry = await controller.prepareComposerSubmit(composer);

      expect(first.failure, isNull);
      expect(first.notice, _proofreadingNotice);
      expect(retry.failure, isNull);
      expect(api.pluginWrites, isEmpty);
      expect(controller.isEnabled(composer), isFalse);
      expect(controller.isEnabled(later), isTrue);

      controller.setEnabled(composer, true);
      final proofread = await controller.prepareComposerSubmit(composer);

      expect(controller.isEnabled(composer), isTrue);
      expect(proofread.failure, isNull);
      expect(proofread.changed, isTrue);
      expect(composer.raw, 'A polished reply.');
    },
  );

  testWidgets('More follows Insert and keeps Proofread labeled on resize', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = await _openReply();
    addTearDown(fixture.shell.dispose);
    await _pumpComposer(tester, fixture.shell);
    await tester.pump();

    final more = find.byKey(const ValueKey('composer-options'));
    final insert = find.byKey(const ValueKey('composer-insert'));
    final control = find.byKey(const ValueKey('composer-proofread-control'));
    expect(more, findsOneWidget);
    expect(control, findsNothing);
    expect(
      tester.getRect(more).left,
      greaterThanOrEqualTo(tester.getRect(insert).right),
    );
    expect(tester.getCenter(more).dy, closeTo(tester.getCenter(insert).dy, 1));
    final semantics = tester.ensureSemantics();
    try {
      expect(tester.getSemantics(more).label, 'More');

      await _openOptions(tester);
      expect(find.text('Proofread'), findsOneWidget);
      expect(tester.getSemantics(control).label, 'Proofread');
    } finally {
      semantics.dispose();
    }
    expect(tester.widget<DDropdownMenuCheckboxItem>(control).checked, isFalse);
    expect(tester.getRect(control).right, lessThanOrEqualTo(360));
    await tester.tap(control);
    await tester.pump();
    expect(tester.widget<DDropdownMenuCheckboxItem>(control).checked, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(control, findsNothing);
    tester.view.physicalSize = const Size(800, 640);
    await tester.pumpAndSettle();
    await _openOptions(tester);
    expect(find.text('Proofread'), findsOneWidget);
    expect(tester.widget<DDropdownMenuCheckboxItem>(control).checked, isTrue);

    tester.view.physicalSize = const Size(360, 640);
    await tester.pumpAndSettle();
    if (control.evaluate().isEmpty) await _openOptions(tester);
    expect(find.text('Proofread'), findsOneWidget);
    expect(tester.getRect(control).right, lessThanOrEqualTo(360));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(tester.widget<DDropdownMenuCheckboxItem>(control).checked, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides More when proofreading is unavailable', (tester) async {
    final fixture = await _openReply(config: const SiteConfig());
    addTearDown(fixture.shell.dispose);
    await _pumpComposer(tester, fixture.shell);
    await tester.pump();

    expect(find.byKey(const ValueKey('composer-options')), findsNothing);
  });

  testWidgets('new-topic footer keeps Create left and Proofread in More', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = await _openReply();
    final composer = ComposerController(_newTopicTarget);
    addTearDown(fixture.shell.dispose);
    addTearDown(composer.dispose);

    for (final width in [280.0, 360.0, 800.0]) {
      tester.view.physicalSize = Size(width, 640);
      await _pumpComposer(tester, fixture.shell, composer: composer);
      await tester.pumpAndSettle();

      expect(find.text('New topic'), findsOneWidget);
      // Actions and tools share one footer line; below the compact
      // breakpoint Create collapses to its icon with the label as tooltip.
      final compact = width < 620;
      final submit = find.byKey(const ValueKey('composer-submit'));
      expect(
        find.descendant(of: submit, matching: find.text('Create topic')),
        compact ? findsNothing : findsOneWidget,
      );
      if (compact) {
        expect(tester.widget<DButton>(submit).tooltip, 'Create topic');
      }
      final panel = tester.getRect(find.byType(ComposerPanel));
      final toolbarFinder = find.byKey(
        const ValueKey('composer-toolbar-scroll'),
      );
      final toolbar = tester.getRect(toolbarFinder);
      expect(tester.getRect(submit).left, closeTo(panel.left + 16, 1));
      expect(toolbar.right, closeTo(panel.right - 16, 1));
      expect(toolbar.center.dy, closeTo(tester.getCenter(submit).dy, 1));
      expect(
        toolbar.left,
        greaterThan(
          tester.getRect(find.byKey(const ValueKey('composer-cancel'))).right,
        ),
      );
      if (width == 280) {
        await tester.drag(toolbarFinder, const Offset(-160, 0));
        await tester.pumpAndSettle();
      }
      await _openOptions(tester);
      expect(find.text('Proofread'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('minimized composer hides More', (tester) async {
    final fixture = await _openReply();
    addTearDown(fixture.shell.dispose);

    await _pumpComposer(tester, fixture.shell, minimized: true);
    await tester.pump();

    expect(find.byKey(const ValueKey('composer-options')), findsNothing);
    expect(
      find.byKey(const ValueKey('composer-proofread-control')),
      findsNothing,
    );
  });

  testWidgets('a later composer restores the remembered choice', (
    tester,
  ) async {
    final first = await _openReply();
    await _pumpComposer(tester, first.shell);
    await tester.pump();
    await _openOptions(tester);
    await tester.tap(find.byKey(const ValueKey('composer-proofread-control')));
    await tester.pump();

    expect(
      await tester.runAsync(
        () => const AiProofreadingPreferenceStore().read(
          siteUrl: _siteUrl,
          userId: _readerId,
        ),
      ),
      isTrue,
    );

    first.shell.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    final second = await _openReply();
    addTearDown(second.shell.dispose);
    await _pumpComposer(tester, second.shell);
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
    await _openOptions(tester);

    expect(
      tester
          .widget<DDropdownMenuCheckboxItem>(
            find.byKey(const ValueKey('composer-proofread-control')),
          )
          .checked,
      isTrue,
    );
  });

  testWidgets('enabled proofreading runs before posting a reply', (
    tester,
  ) async {
    final fixture = await _openReply();
    addTearDown(fixture.shell.dispose);
    await _pumpComposer(tester, fixture.shell);
    await tester.pump();
    fixture.shell.visibleComposer!.text.text = 'this is the reply';
    await _openOptions(tester);
    await tester.tap(find.byKey(const ValueKey('composer-proofread-control')));
    await tester.pump();

    await fixture.shell.submitComposer();

    expect(fixture.api.pluginWrites, hasLength(1));
    expect(fixture.api.created.single['raw'], 'This is the polished reply.');
  });

  testWidgets('unavailable proofreading posts immediately with a toast', (
    tester,
  ) async {
    await tester.runAsync(
      () => const AiProofreadingPreferenceStore().write(
        siteUrl: _siteUrl,
        userId: _readerId,
        enabled: true,
      ),
    );
    final fixture = await _openReply(config: const SiteConfig());
    addTearDown(fixture.shell.dispose);
    final composer = fixture.shell.visibleComposer!;
    composer.text.text = 'this is the original reply';
    await _pumpComposer(tester, fixture.shell, submissionFeedback: true);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('composer-submit')));
    await tester.pumpAndSettle();

    expect(composer.error, isNull);
    expect(fixture.api.pluginWrites, isEmpty);
    expect(fixture.api.created.single['raw'], 'this is the original reply');
    expect(fixture.shell.visibleComposer, isNull);
    expect(find.byType(ComposerPanel), findsNothing);
    expect(find.text(_proofreadingNotice), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text(_proofreadingNotice), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  test(
    'a failed post still reports its error after proofreading fails',
    () async {
      await const AiProofreadingPreferenceStore().write(
        siteUrl: _siteUrl,
        userId: _readerId,
        enabled: true,
      );
      const failure = WriteException(
        WriteFailure.validation,
        errors: ['The site rejected this post.'],
      );
      final fixture = await _openReply(
        proofreadingResponse: const {},
        postingFailure: failure,
      );
      addTearDown(fixture.shell.dispose);
      final composer = fixture.shell.visibleComposer!;
      composer.text.text = 'this is the original reply';
      final notices = <String>[];

      await fixture.shell.submitComposer(onPreparationNotice: notices.add);

      expect(fixture.api.created.single['raw'], 'this is the original reply');
      expect(fixture.shell.visibleComposer, same(composer));
      expect(composer.error, same(failure));
      expect(composer.raw, 'this is the original reply');
      expect(notices, [_proofreadingNotice]);
    },
  );

  testWidgets(
    'a reply in a message topic hides Proofread and posts as written',
    (tester) async {
      await tester.runAsync(
        () => const AiProofreadingPreferenceStore().write(
          siteUrl: _siteUrl,
          userId: _readerId,
          enabled: true,
        ),
      );
      final fixture = await _openReply(privateMessage: true);
      addTearDown(fixture.shell.dispose);
      final composer = fixture.shell.visibleComposer!;
      await _pumpComposer(tester, fixture.shell);
      await tester.pump();

      expect(composer.isPrivateMessage, isTrue);
      expect(find.byKey(const ValueKey('composer-options')), findsNothing);

      composer.text.text = 'this is the private reply';
      await fixture.shell.submitComposer();

      expect(fixture.api.pluginWrites, isEmpty);
      expect(fixture.api.created.single['raw'], 'this is the private reply');
      expect(fixture.shell.visibleComposer, isNull);
    },
  );

  testWidgets('a reply in a message topic is proofread where the site allows', (
    tester,
  ) async {
    await tester.runAsync(
      () => const AiProofreadingPreferenceStore().write(
        siteUrl: _siteUrl,
        userId: _readerId,
        enabled: true,
      ),
    );
    final fixture = await _openReply(
      privateMessage: true,
      config: _configWith(allowedInPrivateMessages: true),
    );
    addTearDown(fixture.shell.dispose);
    await _pumpComposer(tester, fixture.shell);
    await tester.pump();
    fixture.shell.visibleComposer!.text.text = 'this is the private reply';

    await fixture.shell.submitComposer();

    expect(fixture.api.pluginWrites.single.path, aiProofreadingPath);
    expect(fixture.api.created.single['raw'], 'This is the polished reply.');
  });

  for (final scenario in [
    (
      name: 'HTTP 500',
      failure: const WriteException(WriteFailure.unreachable, statusCode: 500),
    ),
    (
      name: 'connection failure',
      failure: const WriteException(WriteFailure.unreachable),
    ),
    (
      name: 'HTTP 403',
      failure: const WriteException(WriteFailure.forbidden, statusCode: 403),
    ),
    (name: 'invalid response', failure: null),
  ]) {
    testWidgets('proofreading ${scenario.name} posts the original reply', (
      tester,
    ) async {
      await tester.runAsync(
        () => const AiProofreadingPreferenceStore().write(
          siteUrl: _siteUrl,
          userId: _readerId,
          enabled: true,
        ),
      );
      final fixture = await _openReply(
        proofreadingResponse: const {},
        proofreadingFailure: scenario.failure,
      );
      addTearDown(fixture.shell.dispose);
      fixture.shell.visibleComposer!.text.text = 'this is the original reply';
      await _pumpComposer(tester, fixture.shell, submissionFeedback: true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('composer-submit')));
      await tester.pumpAndSettle();

      expect(fixture.api.pluginWrites, hasLength(1));
      expect(fixture.api.created.single['raw'], 'this is the original reply');
      expect(fixture.shell.visibleComposer, isNull);
      expect(find.byType(ComposerPanel), findsNothing);
      expect(find.text(_proofreadingNotice), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text(_proofreadingNotice), findsNothing);
    });
  }

  for (final method in ['mobile button', 'Ctrl+Enter', 'Cmd+Enter']) {
    testWidgets(
      'proofreading failure shows a toast using $method',
      (tester) async {
        if (method == 'mobile button') {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
        }
        await tester.runAsync(
          () => const AiProofreadingPreferenceStore().write(
            siteUrl: _siteUrl,
            userId: _readerId,
            enabled: true,
          ),
        );
        final fixture = await _openReply(proofreadingResponse: const {});
        addTearDown(fixture.shell.dispose);
        final composer = fixture.shell.visibleComposer!;
        composer.text.text = 'this is the original reply';
        await _pumpComposer(tester, fixture.shell, submissionFeedback: true);
        await tester.pumpAndSettle();

        if (method == 'mobile button') {
          await tester.tap(find.byKey(const ValueKey('composer-submit')));
        } else {
          composer.focus.requestFocus();
          await tester.pumpAndSettle();
          final modifier = method == 'Ctrl+Enter'
              ? LogicalKeyboardKey.controlLeft
              : LogicalKeyboardKey.metaLeft;
          await tester.sendKeyDownEvent(modifier);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyUpEvent(modifier);
        }
        await tester.pumpAndSettle();

        expect(fixture.api.created.single['raw'], 'this is the original reply');
        expect(fixture.shell.visibleComposer, isNull);
        expect(find.byType(ComposerPanel), findsNothing);
        expect(find.text(_proofreadingNotice), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.text(_proofreadingNotice), findsNothing);
      },
      variant: TargetPlatformVariant.only(
        method == 'mobile button' ? TargetPlatform.iOS : TargetPlatform.macOS,
      ),
    );
  }
}
