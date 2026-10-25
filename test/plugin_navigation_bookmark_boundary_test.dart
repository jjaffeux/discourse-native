import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the sidebar DTO exposes decorations without plugin-owned fields', () {
    final source = File('lib/src/models/sidebar.dart').readAsStringSync();

    expect(source, isNot(contains('avatarUserId')));
    expect(source, isNot(contains('UserStatus')));
    expect(source, isNot(contains('List<SidebarDestination> children')));
    expect(source, contains('SidebarRowDecorationBuilder? prefixBuilder'));
    expect(source, contains('SidebarRowDecorationBuilder? labelSuffixBuilder'));

    final capabilityApi = File(
      'lib/src/plugin_api/site_plugin_api.dart',
    ).readAsStringSync();
    expect(capabilityApi, isNot(contains('UserAvatarPlugin')));
  });

  test('plugin bookmark actions cannot accept topic context', () {
    final source = File(
      'lib/src/plugin_api/bookmark_host.dart',
    ).readAsStringSync();
    final start = source.indexOf('abstract interface class PluginBookmarkHost');
    final end = source.indexOf(
      'abstract interface class PluginBookmarkHostFactory',
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final pluginHost = source.substring(start, end);
    expect(
      pluginHost,
      isNot(contains(RegExp(r'\bBookmarkTargetHost\b'))),
      reason: 'Plugins must not inherit the topic-aware bookmark authority.',
    );
    expect(
      pluginHost,
      isNot(contains(RegExp(r'\btopicId\b'))),
      reason:
          'Optional and nullable topic parameters still grant topic context.',
    );
    expect(pluginHost, contains(RegExp(r'\btargetId\b')));
  });
}
