import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Groups shell authority stops at the composition adapter', () {
    final coordinator = File(
      'lib/src/shell/group_pages_coordinator.dart',
    ).readAsStringSync();
    final host = File('lib/src/shell/group_pages_host.dart').readAsStringSync();
    final port = File('lib/src/shell/group_pages_port.dart').readAsStringSync();
    final directoryView = File(
      'lib/src/shell/groups_page.dart',
    ).readAsStringSync();
    final detailView = File('lib/src/shell/group_page.dart').readAsStringSync();
    final adapter = File(
      'lib/src/shell/group_pages_shell_port.dart',
    ).readAsStringSync();

    for (final source in [coordinator, host, port, directoryView, detailView]) {
      expect(source, isNot(contains("import 'shell_controller.dart'")));
      expect(source, isNot(contains("import 'shell_scope.dart'")));
    }
    expect(coordinator, isNot(contains('package:flutter/')));
    expect(adapter, contains("import 'shell_controller.dart'"));
  });
}
