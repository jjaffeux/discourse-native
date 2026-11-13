import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

const _closureBudgets = <String, (int, int)>{
  'lib/src/shell/do_not_disturb_controller.dart': (10, 0),
  'lib/src/shell/preferences_controller.dart': (38, 0),
  'lib/src/shell/user_summary_controller.dart': (37, 0),
  'lib/src/plugins/chat/chat_transcript_data.dart': (179, 2),
  'lib/src/plugins/discourse_lazy_videos/lazy_embed_parser.dart': (1, 0),
  'lib/src/plugins/discourse_mermaid/mermaid_composer_source.dart': (1, 0),
  'lib/src/shell/site_read_policy.dart': (40, 0),
  'lib/src/shell/preview_requests.dart': (47, 0),
  'lib/src/shell/draft_list_controller.dart': (41, 0),
  'lib/src/shell/composer/block_surface.dart': (265, 137),
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
