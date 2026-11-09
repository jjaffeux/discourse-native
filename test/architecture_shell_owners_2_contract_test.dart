import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

const _owners = [
  'lib/src/shell/topic_channel_router.dart',
  'lib/src/shell/account_destination_bookmarks.dart',
  'lib/src/shell/composer/composer_uploads.dart',
  'lib/src/data/write_credential.dart',
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

  test('the shell no longer prepares composer media', () {
    expect(
      graph.edges['lib/src/shell/shell_controller.dart'],
      isNot(contains('lib/src/data/composer_media_optimizer.dart')),
    );
  });

  test('the shell no longer parses live topic messages', () {
    expect(
      graph.edges['lib/src/shell/shell_controller.dart'],
      isNot(contains('lib/src/models/live_refresh_id.dart')),
    );
  });
}
