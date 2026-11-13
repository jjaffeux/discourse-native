import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

const _closureBudgets = <String, (int, int)>{
  'lib/src/shell/group_pages_port.dart': (83, 0),
  'lib/src/plugins/gamification/gamification_models.dart': (165, 2),
  'lib/src/plugins/poll/poll_composer_parser.dart': (165, 2),
  'lib/src/plugins/local_dates/local_date_composer_parser.dart': (166, 2),
  'lib/src/plugins/chat/chat_stream.dart': (172, 2),
  'lib/src/plugins/chat/chat_composer_target.dart': (165, 2),
  'lib/src/plugins/boards/boards_controller.dart': (167, 2),
  'lib/src/plugins/chat/chat_shell_service.dart': (212, 2),
  'lib/src/shell/topic_list_cursor_coordinator.dart': (87, 0),
  'lib/src/plugins/chat/chat_message_body_staging.dart': (3, 2),
};

void main() {
  final graph = LibraryGraph.load();

  for (final MapEntry(key: path, value: (libraries, widgets))
      in _closureBudgets.entries) {
    test('${path.split('/').last} stays within its dependency budget', () {
      expect(graph.edges, contains(path));
      expect(graph.closureOf(path), hasLength(lessThanOrEqualTo(libraries)));
      expect(
        graph.widgetLibrariesReachedBy(path),
        hasLength(lessThanOrEqualTo(widgets)),
      );
    });
  }
}
