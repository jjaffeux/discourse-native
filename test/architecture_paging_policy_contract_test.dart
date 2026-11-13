import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Call sites of the prefetch distance that consult a [ScrollPagingGate].
const _gatedCalls = {
  'lib/src/plugins/assign/assigned_group_view.dart': 1,
  'lib/src/plugins/chat/chat_channel_view.dart': 3,
  'lib/src/plugins/nested_replies/nested_replies_reader.dart': 1,
  'lib/src/shell/bookmark_list.dart': 2,
  'lib/src/shell/categories_page.dart': 1,
  'lib/src/shell/group/group_members_view.dart': 1,
  'lib/src/shell/topic_list_view.dart': 1,
  'lib/src/shell/user_activity.dart': 4,
  'lib/src/shell/users_page.dart': 1,
};

const _ungatedBudget = 1;

/// Call sites that do not consult the gate where they measure, and why.
const _exceptions = {
  'lib/src/shell/topic_viewport_coordinator.dart': (
    calls: 1,
    gateOwner: null,
    reason:
        'asks once per post window and treats a new reader drag as the '
        'explicit retry, since the reader has no Try again row',
  ),
};

final _call = RegExp(r'\bpaginationPrefetchDistance\(');

const _owner = 'lib/src/utils/paging_policy.dart';

String _withoutComments(String source) =>
    source.replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

Map<String, String> _libSources() => {
  for (final file in Directory('lib').listSync(recursive: true))
    if (file is File && file.path.endsWith('.dart'))
      file.path.replaceAll(r'\', '/'): _withoutComments(
        file.readAsStringSync(),
      ),
};

void main() {
  final sources = _libSources();
  final calls = {
    for (final entry in sources.entries)
      if (entry.key != _owner && _call.hasMatch(entry.value))
        entry.key: _call.allMatches(entry.value).length,
  };

  test('every prefetch call site is accounted for', () {
    expect(calls, {
      ..._gatedCalls,
      for (final entry in _exceptions.entries) entry.key: entry.value.calls,
    });
  });

  test('a prefetch caller consults the gate or is a named exception', () {
    final ungated = {
      for (final path in calls.keys)
        if (!sources[path]!.contains('.admits')) path,
    };
    expect(ungated, _exceptions.keys.toSet());
    expect(
      ungated.fold<int>(0, (total, path) => total + calls[path]!),
      _ungatedBudget,
    );
  });

  test('an exception that names a gate owner still applies the gate', () {
    for (final exception in _exceptions.values) {
      final owner = exception.gateOwner;
      if (owner == null) continue;
      expect(
        sources[owner],
        contains('ScrollPagingGate('),
        reason: exception.reason,
      );
    }
  });
}
