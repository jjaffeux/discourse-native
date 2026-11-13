import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

const _closureBudgets = <String, (int, int)>{
  'lib/src/data/dsa_notices_api.dart': (33, 0),
  'lib/src/data/discourse_search_api.dart': (67, 0),
  'lib/src/shell/global_search_api.dart': (54, 0),
  'lib/src/shell/recent_search_history.dart': (64, 0),
  'lib/src/data/custom_sidebar_sections.dart': (37, 0),
  'lib/src/plugins/nested_replies/nested_replies_reader_memory.dart': (174, 2),
  'lib/src/plugins/post_voting/post_voting_category_controller.dart': (174, 2),
  'lib/src/plugins/voice/voice_call_controller_port.dart': (173, 2),
  'lib/src/shell/current_user_directory.dart': (38, 0),
  'lib/src/shell/instance_rail_transactions.dart': (31, 0),
  'lib/src/shell/topic_metadata_transactions.dart': (117, 1),
  'lib/src/shell/composer/history_scope.dart': (3, 1),
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
