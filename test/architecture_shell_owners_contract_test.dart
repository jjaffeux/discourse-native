import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

const _owners = [
  'lib/src/shell/user_menu_notifications.dart',
  'lib/src/shell/site_read_policy.dart',
  'lib/src/shell/topic_filter_lookups.dart',
];
const _shellLibraries = {
  'lib/src/shell/shell_controller.dart',
  'lib/src/shell/shell_scope.dart',
};

void main() {
  final graph = LibraryGraph.load();

  for (final owner in _owners) {
    test('$owner reaches no shell authority', () {
      expect(graph.closureOf(owner).intersection(_shellLibraries), isEmpty);
    });
  }
}
