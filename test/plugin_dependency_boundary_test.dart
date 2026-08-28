import 'dart:io';

import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

const _pluginIdsByDirectory = <String, String>{
  'assign': 'discourse-assign',
  'chat': 'chat',
  'discourse_ai': 'discourse-ai',
  'discourse_github': 'discourse-github',
  'discourse_lazy_videos': 'discourse-lazy-videos',
  'gifs': 'gifs',
  'local_dates': 'discourse-local-dates',
  'poll': 'poll',
  'reactions': 'discourse-reactions',
  'resenha': 'resenha',
};

const _approvedCrossFeatureContracts = <String, String>{
  'chat->gifs': 'lib/src/plugins/gifs/gifs_contract.dart',
  'local_dates->chat': 'lib/src/plugins/chat/chat_preview_contract.dart',
  'discourse_github->local_dates':
      'lib/src/plugins/local_dates/local_dates_contract.dart',
  'resenha->chat': 'lib/src/plugins/chat/chat_contract.dart',
};

const _removedCompatibilityFiles = <String>{
  'lib/src/plugin_api/chat_preview.dart',
  'lib/src/plugins/core_plugin_manifest.dart',
  'lib/src/plugins/discourse_model_codec.dart',
  'lib/src/plugins/plugin_contracts.dart',
  'lib/src/plugins/plugin_data.dart',
  'lib/src/plugins/plugin_host_ports.dart',
  'lib/src/plugins/plugin_manifest.dart',
  'lib/src/plugins/plugin_registry.dart',
  'lib/src/plugins/plugin_runtime.dart',
  'lib/src/plugins/plugin_scope.dart',
  'lib/src/plugins/plugin_services.dart',
  'lib/src/plugins/site_plugin.dart',
  'lib/src/plugins/site_plugin_api.dart',
  'lib/src/shell/oneboxes/inline.dart',
};

const _forbiddenPluginShellTargets = <String>{
  'lib/src/shell/shell_controller.dart',
  'lib/src/shell/shell_scope.dart',
};

const _forbiddenRawHostAuthorityTargets = <String>{
  'lib/src/data/api_credentials.dart',
  'lib/src/data/authenticator.dart',
  'lib/src/data/site_lifecycle.dart',
  'lib/src/data/site_tracker.dart',
};

const _retiredBroadHostPorts = <String>{
  'corePluginCredentialsPort',
  'corePluginStorePort',
  'corePluginSiteLifecyclePort',
};

const _featureModuleEntrypoints = <String>{
  'assign/assign_module.dart',
  'chat/chat_module.dart',
  'discourse_ai/discourse_ai_module.dart',
  'discourse_github/discourse_github_module.dart',
  'discourse_lazy_videos/discourse_lazy_videos_module.dart',
  'gifs/gifs_module.dart',
  'local_dates/local_dates_module.dart',
  'poll/poll_module.dart',
  'reactions/reactions_module.dart',
  'resenha/resenha_module.dart',
};

final _directiveStatements = RegExp(
  r'''^\s*(?:import|export|part)\s+([^;]+);''',
  multiLine: true,
  dotAll: true,
);
final _quotedUris = RegExp(r'''['"]([^'"]+)['"]''');

void main() {
  test('core never imports or exports a plugin implementation', () {
    final violations = <String>[];

    for (final file in _dartFilesUnder('lib')) {
      final path = _workspacePath(file);
      if (path.startsWith('lib/src/plugins/') ||
          path == 'lib/main.dart' ||
          path == 'lib/discourse_full.dart') {
        continue;
      }

      for (final directive in _localDirectives(file)) {
        if (!directive.target.startsWith('lib/src/plugins/') &&
            directive.target != 'lib/discourse_full.dart') {
          continue;
        }
        violations.add('$path:${directive.line} imports ${directive.uri}');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Plugin implementations may depend on core, but core must extend '
          'through lib/src/plugin_api instead of importing a plugin. Only the '
          'full-build composition roots may assemble bundled plugins.\n'
          '${violations.join('\n')}',
    );
  });

  test('bundled composition imports only feature module entrypoints', () {
    const manifestPath = 'lib/src/plugins/bundled_plugin_manifest.dart';
    final imports = _localDirectives(
      File(manifestPath),
    ).where((directive) => directive.kind == 'import').toList();
    final featureImports = <String>{};
    final violations = <String>[];

    for (final directive in imports) {
      if (directive.uri == '../plugin_api/plugin_manifest.dart') continue;
      if (!_featureModuleEntrypoints.contains(directive.uri)) {
        violations.add(
          '$manifestPath:${directive.line} imports ${directive.uri}',
        );
        continue;
      }
      featureImports.add(directive.uri);
    }

    final missingEntrypoints = _featureModuleEntrypoints.difference(
      featureImports,
    );
    final missingFiles = [
      for (final entrypoint in _featureModuleEntrypoints)
        if (!File('lib/src/plugins/$entrypoint').existsSync()) entrypoint,
    ];

    expect(
      violations,
      isEmpty,
      reason:
          'The bundled composition root may import only the plugin manifest '
          'API and complete feature module entrypoints.\n'
          '${violations.join('\n')}',
    );
    expect(
      missingEntrypoints,
      isEmpty,
      reason:
          'Every bundled feature module must be imported by the composition '
          'root. Missing: ${missingEntrypoints.join(', ')}',
    );
    expect(
      missingFiles,
      isEmpty,
      reason:
          'Every bundled feature owns its production module. Missing: '
          '${missingFiles.join(', ')}',
    );
  });

  test('plugin implementations have one physical owner', () {
    final compatibilityFiles = [
      for (final path in _removedCompatibilityFiles)
        if (File(path).existsSync()) path,
    ];
    final misplacedImplementations = <String>[];
    const pluginMarkupTokens = <String>{
      'data-video-',
      'githubcommit',
      'githubissue',
      'githubpullrequest',
      'lazy-video-container',
    };

    for (final entity in Directory('lib/src/plugins').listSync()) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = _workspacePath(entity);
      if (path != 'lib/src/plugins/bundled_plugin_manifest.dart') {
        misplacedImplementations.add('$path is a root-level plugin file');
      }
    }

    for (final file in _dartFilesUnder('lib/src')) {
      final path = _workspacePath(file);
      if (path.startsWith('lib/src/plugins/')) continue;
      final name = file.uri.pathSegments.last;
      if (name == 'chat_thread_panel_width_store.dart' ||
          name.startsWith('resenha_') ||
          path.contains('/oneboxes/github/')) {
        misplacedImplementations.add(path);
      }
      final source = file.readAsStringSync();
      for (final token in pluginMarkupTokens) {
        if (source.contains(token)) {
          misplacedImplementations.add('$path contains $token');
        }
      }
    }

    expect(
      compatibilityFiles,
      isEmpty,
      reason:
          'The old lib/src/plugins forwarding barrels and eager bundled '
          'registry must stay removed. Import lib/src/plugin_api directly.\n'
          '${compatibilityFiles.join('\n')}',
    );
    expect(
      misplacedImplementations,
      isEmpty,
      reason:
          'Feature-owned implementation files must live below their plugin '
          'directory.\n${misplacedImplementations.join('\n')}',
    );
  });

  test('plugin production code cannot recover the concrete shell', () {
    final violations = <String>[];
    for (final file in _dartFilesUnder('lib/src/plugins')) {
      final path = _workspacePath(file);
      final source = file.readAsStringSync();
      for (final directive in _localDirectives(file)) {
        if (_forbiddenPluginShellTargets.contains(directive.target)) {
          violations.add('$path:${directive.line} imports ${directive.uri}');
        }
      }
      for (final dispatcher in const [
        'PluginUiScope.contextFor(',
        'PluginUiScope.own(',
        'PluginScope.of(',
        'PluginScope.maybeOf(',
        'PluginRegistryScope.maybeOf(',
      ]) {
        if (source.contains(dispatcher)) {
          violations.add('$path calls host-only $dispatcher');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Plugin UI must use owner-scoped PluginUiScope services backed by '
          'declared host ports; global scopes and the concrete shell are not '
          'plugin APIs.\n'
          '${violations.join('\n')}',
    );
  });

  test('bundled modules do not request retired broad host authority', () {
    final violations = <String>[];
    for (final file in _dartFilesUnder('lib/src/plugins')) {
      final path = _workspacePath(file);
      final source = file.readAsStringSync();
      for (final directive in _localDirectives(file)) {
        if (_forbiddenRawHostAuthorityTargets.contains(directive.target)) {
          violations.add('$path:${directive.line} imports ${directive.uri}');
        }
      }
      for (final port in _retiredBroadHostPorts) {
        if (source.contains(port)) violations.add('$path references $port');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Plugins must receive least-privilege request, record, lifecycle, '
          'and channel facades rather than core credentials, Store, '
          'SiteLifecycle, or SiteTracker authority.\n'
          '${violations.join('\n')}',
    );
  });

  test(
    'cross-feature imports use approved contracts and declared dependencies',
    () {
      final descriptors = {
        for (final module in bundledPluginManifest.modules)
          module.descriptor.id.value: module.descriptor,
      };
      final missingModules = <String>[];
      for (final entry in _pluginIdsByDirectory.entries) {
        if (!Directory('lib/src/plugins/${entry.key}').existsSync()) continue;
        if (!descriptors.containsKey(entry.value)) {
          missingModules.add('${entry.key} -> ${entry.value}');
        }
      }

      final violations = <String>[];
      for (final file in _dartFilesUnder('lib/src/plugins')) {
        final sourcePath = _workspacePath(file);
        final sourceDirectory = _pluginDirectory(sourcePath);
        if (sourceDirectory == null) continue;
        final sourceId = _pluginIdsByDirectory[sourceDirectory];
        if (sourceId == null) {
          violations.add('$sourcePath belongs to an unmapped plugin directory');
          continue;
        }

        for (final directive in _localDirectives(file)) {
          final targetDirectory = _pluginDirectory(directive.target);
          if (targetDirectory == null) {
            if (directive.target.startsWith('lib/src/plugins/')) {
              violations.add(
                '$sourcePath:${directive.line} imports root plugin file '
                '${directive.target}',
              );
            }
            continue;
          }
          if (targetDirectory == sourceDirectory) continue;

          final targetId = _pluginIdsByDirectory[targetDirectory];
          if (targetId == null) {
            violations.add(
              '$sourcePath:${directive.line} targets unmapped '
              '${directive.target}',
            );
            continue;
          }
          final edge = '$sourceDirectory->$targetDirectory';
          final approvedTarget = _approvedCrossFeatureContracts[edge];
          if (directive.target != approvedTarget) {
            violations.add(
              '$sourcePath:${directive.line} imports ${directive.target}; '
              'approved contract for $edge is ${approvedTarget ?? 'none'}',
            );
          }
          final descriptor = descriptors[sourceId];
          final hasRuntimeDependency =
              descriptor?.dependencies.any(
                (dependency) => dependency.id.value == targetId,
              ) ??
              false;
          final hasStaticContributionAuthority =
              descriptor?.staticContributionTargets.any(
                (target) => target.id.value == targetId,
              ) ??
              false;
          if (!hasRuntimeDependency && !hasStaticContributionAuthority) {
            violations.add(
              '$sourcePath:${directive.line} imports $targetId without a '
              'runtime dependency or static contribution authority in '
              '$sourceId',
            );
          }
        }
      }

      expect(
        missingModules,
        isEmpty,
        reason:
            'Every physical bundled plugin directory must correspond to its '
            'manifest descriptor.\n${missingModules.join('\n')}',
      );
      expect(
        violations,
        isEmpty,
        reason:
            'Cross-feature source dependencies must pass through a named '
            'contract and have matching runtime dependency or static '
            'contribution authority.\n'
            '${violations.join('\n')}',
      );
    },
  );

  test('plugins cannot import the concrete site tracker', () {
    final violations = <String>[];

    for (final file in _dartFilesUnder('lib/src/plugins')) {
      final path = _workspacePath(file);
      for (final directive in _localDirectives(file)) {
        if (directive.target != 'lib/src/data/site_tracker.dart') continue;
        violations.add('$path:${directive.line} imports ${directive.uri}');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Plugins receive scoped live-channel handles from the host and must '
          'not import SiteTracker, which also exposes core-channel, polling, '
          'and lifecycle controls.\n${violations.join('\n')}',
    );
  });

  test('plugin controllers do not resolve ambient runtime facilities', () {
    final violations = <String>[];

    for (final file in _dartFilesUnder('lib/src/plugins')) {
      final path = _workspacePath(file);
      final source = file.readAsStringSync();
      for (final token in const [
        'DiagnosticsSink.current',
        'PluginDiagnosticsReporter.ambient',
      ]) {
        if (source.contains(token)) violations.add('$path uses $token');
      }
      if (path != 'lib/src/plugins/local_dates/local_dates_module.dart') {
        for (final token in const [
          'LocalDateEnvironment.instance',
          'TimezoneEnvironment.instance',
        ]) {
          if (source.contains(token)) violations.add('$path uses $token');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Plugin controllers receive diagnostics and timezone facilities '
          'through module/session construction. Only the Local Dates module '
          'entrypoint may choose the production timezone environment.\n'
          '${violations.join('\n')}',
    );
  });

  test('core site and current-user models do not own optional schemas', () {
    final siteConfig = File(
      'lib/src/models/site_config.dart',
    ).readAsStringSync();
    final discourseUser = File(
      'lib/src/models/discourse_user.dart',
    ).readAsStringSync();
    final modelCodec = File(
      'lib/src/plugin_api/discourse_model_codec.dart',
    ).readAsStringSync();

    for (final identifier in const [
      'mainReaction',
      'pollMaximumOptions',
      'localDatesEnabled',
      'gifsEnabled',
      'assignStatusesEnabled',
      'chatUploadsEnabled',
      'ResenhaClientConfig',
    ]) {
      expect(
        siteConfig,
        isNot(contains(identifier)),
        reason: '$identifier belongs in its plugin-owned settings model.',
      );
    }
    for (final identifier in const [
      'canCreatePoll',
      'canAssignGlobally',
      'hasChatEnabled',
      'ChatHeaderIndicatorPreference',
      'lastChatChannelId',
      'ignoredUsernames',
    ]) {
      expect(
        discourseUser,
        isNot(contains(identifier)),
        reason: '$identifier belongs in its plugin-owned current-user model.',
      );
    }
    expect(
      modelCodec,
      isNot(contains('ignored_users')),
      reason: 'ignored_users belongs to Chat\'s current-user wire reader.',
    );
  });

  test('core totals do not own Chat counters or wire fields', () {
    for (final path in const [
      'lib/src/models/notification_totals.dart',
      'lib/src/shell/account_activity_controller.dart',
      'lib/src/data/discourse_api.dart',
    ]) {
      final source = File(path).readAsStringSync();
      for (final identifier in const [
        'chat_notifications',
        'chatNotifications',
        'hasChatEnabled',
        'withChatNotificationsDelta',
      ]) {
        expect(
          source,
          isNot(contains(identifier)),
          reason: '$identifier belongs to Chat, not $path.',
        );
      }
    }
  });

  test('core notifications do not own optional feature wire schemas', () {
    for (final path in const [
      'lib/src/models/notification.dart',
      'lib/src/plugin_api/notification_types.dart',
      'lib/src/plugin_api/notification_feed_host.dart',
      'lib/src/shell/notification_list.dart',
      'lib/src/data/discourse_api.dart',
      'lib/src/data/discourse_api_contracts.dart',
    ]) {
      final source = File(path).readAsStringSync();
      for (final identifier in const [
        'chat_mention',
        'chat_channel_id',
        'mentioned_by_username',
        'assigned',
        'reaction',
        'following_replied',
        'votes_released',
      ]) {
        expect(
          source,
          isNot(contains(identifier)),
          reason: '$identifier belongs to an optional feature, not $path.',
        );
      }
    }
  });

  test('core flag models keep optional target names opaque', () {
    final postFlag = File('lib/src/models/post_flag.dart').readAsStringSync();

    expect(postFlag, contains('appliesToTarget'));
    expect(postFlag, isNot(contains('appliesToChatMessage')));
    expect(
      postFlag,
      isNot(contains('Chat::Message')),
      reason: 'The Chat plugin owns its flag-target wire name.',
    );
  });

  test('core recommendation persistence does not own plugin migrations', () {
    final tabStore = File(
      'lib/src/data/topic_recommendations_tab_store.dart',
    ).readAsStringSync();

    expect(tabStore, contains('migrateLegacyStoredId'));
    expect(tabStore, isNot(contains('discourse-ai/related')));
    expect(
      tabStore,
      isNot(contains(RegExp(r'''["']related["']'''))),
      reason: 'The Discourse AI codec owns its legacy stored value.',
    );
  });

  test('deleted concrete-shell compatibility extensions stay deleted', () {
    for (final path in const [
      'lib/src/plugins/assign/assignment_shell_extension.dart',
      'lib/src/plugins/chat/chat_shell_extension.dart',
      'lib/src/plugins/resenha/resenha_shell_extension.dart',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }
    expect(
      File('lib/src/plugins/chat/chat_shell_service.dart').readAsStringSync(),
      isNot(contains('on ShellController')),
    );
    expect(
      File(
        'lib/src/plugins/resenha/resenha_shell_service.dart',
      ).readAsStringSync(),
      isNot(contains('on ShellController')),
    );
  });
}

Iterable<File> _dartFilesUnder(String path) sync* {
  for (final entity in Directory(path).listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}

Iterable<_LocalDirective> _localDirectives(File file) sync* {
  final source = file.readAsStringSync();
  final sourcePath = _workspacePath(file);
  for (final statement in _directiveStatements.allMatches(source)) {
    final kind = RegExp(
      r'^\s*(import|export|part)',
    ).firstMatch(statement.group(0)!)!.group(1)!;
    for (final match in _quotedUris.allMatches(statement.group(1)!)) {
      final uri = match.group(1)!;
      final target = _resolveLocalUri(sourcePath, uri);
      if (target == null) continue;
      yield _LocalDirective(
        kind: kind,
        uri: uri,
        target: target,
        line: '\n'.allMatches(source.substring(0, statement.start)).length + 1,
      );
    }
  }
}

String? _resolveLocalUri(String sourcePath, String uri) {
  if (uri.startsWith('package:discourse_native/')) {
    return 'lib/${uri.substring('package:discourse_native/'.length)}';
  }
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return null;
  final source = File(sourcePath).absolute;
  return _workspacePath(File.fromUri(source.parent.uri.resolve(uri)));
}

String? _pluginDirectory(String path) =>
    RegExp(r'^lib/src/plugins/([^/]+)/').firstMatch(path)?.group(1);

String _workspacePath(File file) {
  final absolute = file.absolute.path.replaceAll('\\', '/');
  final root = Directory.current.absolute.path.replaceAll('\\', '/');
  return absolute.startsWith('$root/')
      ? absolute.substring(root.length + 1)
      : absolute;
}

final class _LocalDirective {
  const _LocalDirective({
    required this.kind,
    required this.uri,
    required this.target,
    required this.line,
  });

  final String kind;
  final String uri;
  final String target;
  final int line;
}
