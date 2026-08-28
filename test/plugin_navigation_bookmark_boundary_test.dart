import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the sidebar DTO contains no Chat or voice-room record shape', () {
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
    expect(pluginHost, isNot(contains('implements BookmarkTargetHost')));
    expect(pluginHost, isNot(contains('required int topicId')));
    expect(pluginHost, contains('required int targetId'));
  });
}
