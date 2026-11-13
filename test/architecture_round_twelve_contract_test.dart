import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

const _closureBudgets = <String, (int, int)>{
  'lib/src/data/discourse_transport.dart': (31, 0),
  'lib/src/data/discourse_plugin_transport.dart': (33, 0),
  'lib/src/data/site_message_bus_bootstrap.dart': (37, 0),
  'lib/src/data/instance_store.dart': (42, 0),
  'lib/src/plugins/chat/chat_composer_draft_session.dart': (213, 2),
  'lib/src/plugins/gifs/gif_picker_session_impl.dart': (179, 2),
  'lib/src/plugins/nested_replies/nested_replies_admin_controller.dart': (177, 2),
  'lib/src/shell/header_preferences_controller.dart': (7, 0),
  'lib/src/shell/message_archive_transactions.dart': (126, 1),
  'lib/src/shell/topic_navigation_attempts.dart': (120, 1),
  'lib/src/shell/composer/slash_query.dart': (5, 0),
};

void main() {
  final graph = LibraryGraph.load();

  for (final MapEntry(key: path, value: (libraries, widgets))
      in _closureBudgets.entries) {
    test('${path.split('/').last} stays within its dependency budget', () {
      expect(graph.edges, contains(path));
      expect(graph.closureOf(path).length, lessThanOrEqualTo(libraries));
      expect(
        graph.widgetLibrariesReachedBy(path).length,
        lessThanOrEqualTo(widgets),
      );
    });
  }
}
