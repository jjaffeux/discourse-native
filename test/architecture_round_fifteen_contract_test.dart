import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

const _closureBudgets = <String, (int, int)>{
  'lib/src/shell/topic_read_controller.dart': (42, 0),
  'lib/src/data/discourse_topic_api.dart': (77, 0),
  'lib/src/shell/topic_feed_controller.dart': (50, 0),
  'lib/src/shell/account_new_topic_dismissals.dart': (53, 0),
  'lib/src/shell/bookmark_transactions.dart': (47, 0),
  'lib/src/plugins/chat/chat_contract.dart': (188, 2),
  'lib/src/plugins/chat/chat_inbox_rooms.dart': (178, 2),
  'lib/src/plugins/voice/voice_controller.dart': (204, 3),
  'lib/src/plugins/discourse_events/event_onebox_data.dart': (176, 2),
  'lib/src/plugins/discourse_ai/ai_related_topics.dart': (176, 2),
  'lib/src/shell/dsa_notice_controller.dart': (6, 0),
  'lib/src/shell/group_write.dart': (39, 0),
  'lib/src/shell/checklist_transactions.dart': (47, 0),
  'lib/src/shell/post_checklist_write.dart': (41, 0),
  'lib/src/shell/composer/selection_colors.dart': (203, 133),
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
