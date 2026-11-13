import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

const _closureBudgets = <String, (int, int)>{
  'lib/src/data/account_session_coordinator.dart': (53, 0),
  'lib/src/data/discourse_account_api.dart': (77, 0),
  'lib/src/data/discourse_site_api.dart': (76, 0),
  'lib/src/data/discourse_composer_api.dart': (77, 0),
  'lib/src/plugins/nested_replies/nested_replies_services.dart': (178, 2),
  'lib/src/plugins/nested_replies/nested_replies_bulk_controller.dart': (174, 2),
  'lib/src/plugins/policy/policy_email_preferences.dart': (172, 2),
  'lib/src/plugins/voice/voice_room_onebox_data.dart': (1, 0),
  'lib/src/shell/post_mutation_policy.dart': (117, 1),
  'lib/src/shell/selected_post_moderation.dart': (119, 1),
  'lib/src/shell/topic_action_transactions.dart': (118, 1),
  'lib/src/shell/composer/draft_preview.dart': (181, 133),
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
