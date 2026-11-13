import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_admin_controller.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_api.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_data.dart';
import 'package:flutter/foundation.dart';

import '../test/support/fakes.dart';

const _delay = Duration(milliseconds: 30);

Future<void> main() async {
  final samples = <int>[];
  for (var run = 0; run < 7; run++) {
    final reader = _Reader();
    final api = _Api();
    final controller = NestedRepliesAdminController(
      reader: reader,
      api: NestedRepliesApi(api, const DiscourseModelCodec.core()),
      categories: PluginCategorySettingsApi(api),
      settings: const NestedRepliesSettings(enabled: true),
      requests: _Requests(),
    );
    controller.needsRecheck = true;
    final watch = Stopwatch()..start();
    await controller.recheck();
    watch.stop();
    if (reader.refreshes != 1 ||
        api.gets != 1 ||
        controller.needsRecheck ||
        controller.problem != null ||
        controller.category?.name != 'Sailing') {
      throw StateError('Topic and category settings did not reconcile');
    }
    controller.dispose();
    reader.dispose();
    if (run >= 2) samples.add(watch.elapsedMicroseconds);
  }
  samples.sort();
  stdout.writeln(jsonEncode({'recheck_nested_reply_settings': samples[2]}));
  exit(0);
}

class _Reader extends ChangeNotifier implements PluginTopicReader {
  int refreshes = 0;
  @override
  String get siteUrl => 'https://forum.example';
  @override
  bool get isCurrent => true;
  @override
  bool get foreground => true;
  @override
  bool get currentUserStaff => true;
  @override
  TopicDetail get topic =>
      const TopicDetail(id: 7, title: 'Question', categoryId: 3, stream: []);
  @override
  Future<void> refreshMetadata() async {
    await Future<void>.delayed(_delay);
    refreshes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Requests implements PluginRequestHost, PluginSiteLease {
  @override
  bool get isCurrent => true;
  @override
  PluginSiteLease capture(String siteUrl) => this;
  @override
  bool commit(void Function() callback) {
    callback();
    return true;
  }

  @override
  void Function() onRetire(void Function() observer) => () {};
  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async =>
      const PluginRequestCredentials(apiKey: 'key', clientId: '');
  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async =>
      throw StateError('Unexpected write');
}

class _Api extends FakeDiscourseApi {
  int gets = 0;
  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    if (apiKey != 'key' || !path.contains('/3')) {
      throw StateError('Unexpected category read $path');
    }
    gets++;
    await Future<void>.delayed(_delay);
    return {
      'category': {
        'id': 3,
        'name': 'Sailing',
        'can_edit': true,
        'category_setting': {'nested_replies_default': true},
      },
    };
  }
}
