import 'dart:async';

import 'package:discourse_native/discourse_ui.dart'
    show DDropdownMenuCheckboxItem;
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
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

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

final _enabledConfig = SiteConfig(
  plugins: PluginData.none.withValue(
    discourseAiSettingsDataKey,
    const DiscourseAiSettings(enabled: true, helperEnabled: true),
  ),
);

final _allowedUser = DiscourseUser(
  id: 7,
  username: 'reader',
  plugins: PluginData.none.withValue(
    discourseAiCurrentUserDataKey,
    const DiscourseAiCurrentUser(canUseAssistant: true),
  ),
);

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

final class _FreshAccountHost implements PluginFreshAccountHost {
  const _FreshAccountHost(this.data);

  final PluginData data;

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

AiProofreadingController _controller({
  SiteConfig? config,
  DiscourseUser? user,
  FakeDiscourseApi? api,
  SiteLifecycle? lifecycle,
  AiProofreadingPreferenceStore preferences =
      const AiProofreadingPreferenceStore(),
}) {
  final credentials = FakeApiCredentialReader()..keys[_siteUrl] = 'api-key';
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
      credentials: credentials,
      lifecycle: lifecycle,
    ),
    siteState: PluginSiteStateHost(
      currentUserFor: (_) => user,
      siteConfigFor: (_) => config ?? _enabledConfig,
    ),
    freshAccount: _FreshAccountHost((user ?? _allowedUser).plugins),
    preferences: preferences,
  );
}

Future<({ShellController shell, FakeDiscourseApi api})> _openReply({
  Map<String, dynamic>? proofreadingResponse = const {
    'suggestions': ['This is the polished reply.'],
  },
  WriteException? proofreadingFailure,
  SiteConfig? config,
}) async {
  final api = FakeDiscourseApi(
    user: _allowedUser,
    feeds: const {'/latest.json': <Topic>[]},
    topics: {
      7: topicPayload(id: 7, title: 'Native writing', canCreatePost: true),
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
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.dark,
    home: ShellScope(
      controller: shell,
      child: Scaffold(
        body: ComposerPanel(
          composer: composer ?? shell.visibleComposer!,
          minimized: minimized,
          height: minimized ? null : 500,
        ),
      ),
    ),
  ),
);

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
      }, _siteUrl),
      const DiscourseAiSettings(enabled: true, helperEnabled: true),
    );
    expect(plugin.readCurrentUser(const {}, _siteUrl), isNull);
    expect(
      plugin.readCurrentUser(const {'can_use_assistant': true}, _siteUrl),
      const DiscourseAiCurrentUser(canUseAssistant: true),
    );
  });

  test('is available for new topics and public replies only', () {
    final controller = _controller();
    addTearDown(controller.dispose);
    final reply = ComposerController(_replyTarget);
    final newTopic = ComposerController(_newTopicTarget);
    final message = ComposerController(
      const ComposerTarget(
        siteUrl: _siteUrl,
        topicId: 0,
        slug: '',
        topicTitle: 'New message',
        mode: ComposerMode.privateMessage,
        targetRecipients: 'sam',
      ),
    );
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
    addTearDown(edit.dispose);

    expect(controller.isAvailable(reply), isTrue);
    expect(controller.isAvailable(newTopic), isTrue);
    expect(controller.isAvailable(message), isFalse);
    expect(controller.isAvailable(edit), isFalse);
  });

  test('stays hidden without both AI settings and user permission', () {
    final disabled = _controller(config: const SiteConfig.unknown());
    final disallowed = _controller(
      user: const DiscourseUser(id: 7, username: 'reader'),
    );
    final composer = ComposerController(_replyTarget);
    addTearDown(disabled.dispose);
    addTearDown(disallowed.dispose);
    addTearDown(composer.dispose);

    expect(disabled.isAvailable(composer), isFalse);
    expect(disallowed.isAvailable(composer), isFalse);
  });

  test('remembers the choice independently for each forum', () async {
    const store = AiProofreadingPreferenceStore();

    expect(await store.read(siteUrl: _siteUrl), isFalse);

    await store.write(siteUrl: _siteUrl, enabled: true);

    expect(await store.read(siteUrl: _siteUrl), isTrue);
    expect(await store.read(siteUrl: 'https://other.discourse.org'), isFalse);
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
      expect(composer.raw, 'A polished reply.');
      expect(api.pluginWrites.single.path, aiProofreadingPath);
      expect(api.pluginWrites.single.body, {
        'text': 'a reply with typo',
        'mode': 'proofread',
      });
    },
  );

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

    expect(result.failure?.failure, WriteFailure.conflict);
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
    await _openOptions(tester);
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
      final submit = find.byKey(const ValueKey('composer-submit'));
      expect(
        find.descendant(
          of: submit,
          matching: find.text(width < 500 ? 'Create' : 'Create topic'),
        ),
        findsOneWidget,
      );
      final panel = tester.getRect(find.byType(ComposerPanel));
      final toolbarFinder = find.byKey(
        const ValueKey('composer-toolbar-scroll'),
      );
      final toolbar = tester.getRect(toolbarFinder);
      expect(tester.getRect(submit).left, closeTo(panel.left + 12, 1));
      expect(toolbar.right, closeTo(panel.right - 12, 1));
      if (width < 620) {
        expect(
          toolbar.top,
          greaterThanOrEqualTo(tester.getRect(submit).bottom),
        );
      } else {
        expect(toolbar.left, greaterThan(tester.getRect(submit).right));
      }
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
        () => const AiProofreadingPreferenceStore().read(siteUrl: _siteUrl),
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

  for (final scenario in [
    (
      name: 'HTTP 500',
      failure: const WriteException(WriteFailure.unreachable, statusCode: 500),
    ),
    (
      name: 'connection failure',
      failure: const WriteException(WriteFailure.unreachable),
    ),
    (name: 'invalid response', failure: null),
  ]) {
    testWidgets('proofreading ${scenario.name} posts the original reply', (
      tester,
    ) async {
      final fixture = await _openReply(
        proofreadingResponse: const {},
        proofreadingFailure: scenario.failure,
      );
      addTearDown(fixture.shell.dispose);
      await _pumpComposer(tester, fixture.shell);
      await tester.pump();
      fixture.shell.visibleComposer!.text.text = 'this is the original reply';
      await _openOptions(tester);
      await tester.tap(
        find.byKey(const ValueKey('composer-proofread-control')),
      );
      await tester.pump();

      await fixture.shell.submitComposer();

      expect(fixture.api.pluginWrites, hasLength(1));
      expect(fixture.api.created.single['raw'], 'this is the original reply');
      expect(fixture.shell.visibleComposer, isNull);
    });
  }
}
