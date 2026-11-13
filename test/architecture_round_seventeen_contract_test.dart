import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

const _closureBudgets = <String, (int, int)>{
  'lib/src/shell/account_activity_controller.dart': (54, 0),
  'lib/src/shell/account_history_feed_owners.dart': (49, 0),
  'lib/src/shell/topic_filter_lookups.dart': (46, 0),
  'lib/src/shell/composer/composer_identity_directory.dart': (76, 0),
  'lib/src/shell/site_capabilities.dart': (43, 0),
  'lib/src/plugins/discourse_github/oneboxes/github_onebox_data.dart': (183, 2),
  'lib/src/plugins/discourse_events/event_submit_preparer.dart': (184, 2),
  'lib/src/plugins/chat/chat_preferences.dart': (344, 136),
  'lib/src/shell/bookmark_link_resolver.dart': (49, 0),
  'lib/src/shell/flag_transactions.dart': (44, 0),
  'lib/src/shell/notification_feed_refresh_owner.dart': (34, 0),
  'lib/src/shell/composer/slash_menu.dart': (182, 133),
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
