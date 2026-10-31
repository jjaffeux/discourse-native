import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://forum.example';
const _notification = DiscourseNotification.test(
  id: 7,
  typeId: NotificationTypeId(2),
  topicId: 42,
  slug: 'safe-topic',
  postNumber: 3,
  title: 'Topic',
  data: {'url': 'https://outside.example/private'},
);

void main() {
  test(
    'session strategies extend existing types only while enabled for a site',
    () async {
      final plugins = PluginInstaller.install(
        const PluginManifest([_Module('presentation', _Strategy.new)]),
      );
      addTearDown(plugins.close);
      final first = plugins.openSession(const PluginHostBindings.empty());
      final second = plugins.openSession(const PluginHostBindings.empty());
      addTearDown(first.close);
      addTearDown(second.close);
      final strategy =
          first.capabilities<PluginNotificationPresentationStrategy>().single
              as _Strategy;
      final baseline = plugins.registry.resolveNotification(
        _site,
        _notification,
      );

      expect(
        first.resolveNotification(plugins.registry, _site, _notification).path,
        baseline.path,
      );
      strategy.enabled = true;
      expect(
        first.resolveNotification(plugins.registry, _site, _notification).path,
        '/t/safe-topic/42/8?view=contributed',
      );
      expect(
        second.resolveNotification(plugins.registry, _site, _notification).path,
        baseline.path,
      );
      expect(
        first
            .resolveNotification(
              plugins.registry,
              'https://other.example',
              _notification,
            )
            .path,
        baseline.path,
      );
      await first.close();
      expect(
        first.resolveNotification(plugins.registry, _site, _notification).path,
        baseline.path,
      );
    },
  );

  test(
    'declining, throwing, and unsafe strategies retain the original safe route',
    () {
      for (final result in [
        null,
        'https://outside.example/private',
        '//outside.example',
        '/bad\npath',
        '/bad\\path',
      ]) {
        final plugins = PluginInstaller.install(
          PluginManifest([
            _Module(
              'presentation',
              () => _Strategy()
                ..enabled = true
                ..path = result,
            ),
          ]),
        );
        addTearDown(plugins.close);
        final session = plugins.openSession(const PluginHostBindings.empty());
        addTearDown(session.close);
        final baseline = plugins.registry.resolveNotification(
          _site,
          _notification,
        );
        expect(
          session
              .resolveNotification(plugins.registry, _site, _notification)
              .path,
          baseline.path,
        );
      }
      final plugins = PluginInstaller.install(
        PluginManifest([
          _Module(
            'presentation',
            () => _Strategy()
              ..enabled = true
              ..fail = true,
          ),
        ]),
      );
      addTearDown(plugins.close);
      final session = plugins.openSession(const PluginHostBindings.empty());
      addTearDown(session.close);
      expect(
        session
            .resolveNotification(plugins.registry, _site, _notification)
            .path,
        '/t/safe-topic/42/3',
      );
    },
  );

  test(
    'two enabled strategies cannot silently claim the same notification',
    () {
      final plugins = PluginInstaller.install(
        PluginManifest([
          _Module('one', () => _Strategy()..enabled = true),
          _Module('two', () => _Strategy()..enabled = true),
        ]),
      );
      addTearDown(plugins.close);
      final session = plugins.openSession(const PluginHostBindings.empty());
      addTearDown(session.close);
      expect(
        () =>
            session.resolveNotification(plugins.registry, _site, _notification),
        throwsStateError,
      );
    },
  );

  test('session retirement during resolution suppresses the contribution', () {
    late PluginSession session;
    final plugins = PluginInstaller.install(
      PluginManifest([
        _Module(
          'presentation',
          () => _Strategy()
            ..enabled = true
            ..onResolve = () => unawaited(session.close()),
        ),
      ]),
    );
    addTearDown(plugins.close);
    session = plugins.openSession(const PluginHostBindings.empty());
    addTearDown(session.close);
    expect(
      session.resolveNotification(plugins.registry, _site, _notification).path,
      '/t/safe-topic/42/3',
    );
  });
}

final class _Module implements PluginModule {
  const _Module(this.id, this.strategy);
  final String id;
  final PluginNotificationPresentationStrategy Function() strategy;

  @override
  PluginDescriptor get descriptor => PluginDescriptor(id: PluginId(id));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addSession(
      (_, _) => PluginSessionContribution(
        lifecycle: _Lifecycle(),
        capabilities: [strategy()],
      ),
    );
  }
}

final class _Lifecycle extends PluginSessionLifecycle {}

final class _Strategy implements PluginNotificationPresentationStrategy {
  bool enabled = false;
  bool fail = false;
  String? path = '/t/safe-topic/42/8?view=contributed';
  void Function()? onResolve;

  @override
  ResolvedNotification? resolveNotification(
    PluginNotificationPresentationContext context,
  ) {
    if (!enabled || context.siteUrl != _site || path == null) return null;
    onResolve?.call();
    if (fail) throw const FormatException('Malformed contribution');
    return ResolvedNotification(
      presentation: context.fallback.presentation,
      path: path,
    );
  }
}
