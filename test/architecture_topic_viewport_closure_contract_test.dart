import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

const _coordinator = 'lib/src/shell/topic_viewport_coordinator.dart';
const _shell = 'lib/src/shell/shell_controller.dart';

void main() {
  test(
    'the topic viewport coordinator compiles without the shell controller',
    () {
      final closure = LibraryGraph.load().closureOf(_coordinator);
      // ignore: avoid_print
      print('PERF_PROOF viewport-off-shell reach=${closure.length}');
      expect(
        closure,
        isNot(contains(_shell)),
        reason:
            'The coordinator is closure-based; the adapters that read the '
            'shell live in topic_viewport_shell_binding.dart.',
      );
    },
  );
}
