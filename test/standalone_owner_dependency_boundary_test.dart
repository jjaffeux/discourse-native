import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/owner_dependency_graph.dart';

const _owners = {
  'lib/src/plugins/chat/chat_thread_metadata_owner.dart',
  'lib/src/plugins/voice/voice_incoming_calls.dart',
  'lib/src/shell/account_history_feed_owners.dart',
  'lib/src/shell/bookmark_link_resolver.dart',
  'lib/src/shell/checklist_transactions.dart',
  'lib/src/shell/flag_transactions.dart',
  'lib/src/shell/account_new_topic_dismissals.dart',
  'lib/src/shell/notification_feed_refresh_owner.dart',
  'lib/src/shell/cooking_context_owner.dart',
  'lib/src/shell/topic_tracking_directory.dart',
  'lib/src/shell/topic_reader_projections.dart',
  'lib/src/shell/preview_loading.dart',
  'lib/src/shell/profile_write_transactions.dart',
};

void main() {
  test('standalone owners keep shell authority outside their libraries', () {
    final files = Directory('lib')
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final graph = OwnerDependencyGraph({
      for (final file in files) file.path: file.readAsStringSync(),
    });
    final violations = graph.violations(
      owners: _owners,
      forbidden: {
        'lib/src/shell/shell_controller.dart',
        'lib/src/shell/shell_scope.dart',
      },
    );
    expect(violations, isEmpty, reason: violations.join('\n\n'));
  });
}
