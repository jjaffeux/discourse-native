import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/groups_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_model_codec.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/shell/groups_controller.dart';
import 'package:discourse_plugin_api/testing.dart';
import 'package:flutter/widgets.dart';

import '../test/support/fakes.dart' show FakeApiCredentialReader;

const _site = 'https://forum.example';
const _instance = DiscourseInstance(
  url: _site,
  title: 'Forum',
  user: DiscourseUser(username: 'sam'),
);
const _group = Group(id: 7, name: 'support');
const _latency = Duration(milliseconds: 30);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final times = <int>[];
  for (var i = 0; i < 7; i++) {
    final time = await _addMember();
    if (i >= 2) times.add(time);
  }
  times.sort();
  stdout.writeln(jsonEncode({'add_group_member_and_refresh': times[2]}));
  exit(0);
}

Future<int> _addMember() async {
  var added = false;
  final transport = RecordingPluginTransport(
    responders: {
      'PUT /groups/7/members.json': (request) async {
        if (request.body['usernames'] != 'ada') {
          throw StateError('Unexpected member');
        }
        await Future<void>.delayed(_latency);
        added = true;
        return {'success': 'OK'};
      },
      'GET /groups/support.json': (_) async {
        await Future<void>.delayed(_latency);
        return {
          'group': {'id': 7, 'name': 'support', 'user_count': added ? 2 : 1},
        };
      },
      'GET /groups/support/members.json?offset=0&limit=50&asc=true': (_) async {
        await Future<void>.delayed(_latency);
        return {
          'members': [
            {'id': 1, 'username': 'sam'},
            if (added) {'id': 2, 'username': 'ada'},
          ],
          'meta': {'total': added ? 2 : 1, 'offset': 0, 'limit': 50},
        };
      },
    },
  );
  final controller = GroupsController(
    api: GroupsApi(transport, const DiscourseModelCodec.core()),
    credentials: FakeApiCredentialReader()..keys[_site] = 'key',
    lifecycle: SiteLifecycle(),
  );
  try {
    await controller.loadDetail(_instance, _group.name);
    await controller.loadMembers(_instance, _group.name);
    final watch = Stopwatch()..start();
    final result = await controller.addMembers(
      _instance,
      _group,
      GroupAddMembersCommand(usernames: const ['ada']),
    );
    watch.stop();
    if (!result.canApplyLocally ||
        controller.detailState(_site, _group.name).detail?.group.userCount !=
            2 ||
        controller.membersState(_site, _group.name).members.last.username !=
            'ada' ||
        transport.writes.length != 1 ||
        transport.reads.length != 4 ||
        transport.requests.any((request) => request.apiKey != 'key')) {
      throw StateError('Group membership or group detail was not refreshed');
    }
    return watch.elapsedMicroseconds;
  } finally {
    controller.dispose();
  }
}
