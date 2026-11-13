import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

const _closureBudgets = <String, (int, int)>{
  'lib/src/data/write_credential.dart': (7, 0),
  'lib/src/data/site_tracker.dart': (16, 0),
  'lib/src/data/sidebar_icon_loader.dart': (10, 0),
  'lib/src/data/current_user_reconciler.dart': (17, 0),
  'lib/src/plugins/discourse_math/math_settings.dart': (174, 2),
  'lib/src/plugins/discourse_math/math_source.dart': (175, 2),
  'lib/src/plugins/gamification/gamification_api.dart': (173, 2),
  'lib/src/plugins/gamification/gamification_controller.dart': (175, 2),
  'lib/src/plugins/gamification/gamification_labels.dart': (173, 2),
  'lib/src/models/youtube_video_data.dart': (3, 0),
  'lib/src/plugins/discourse_lazy_videos/lazy_youtube_parser.dart': (5, 0),
  'lib/src/shell/mobile_presentation.dart': (45, 1),
  'lib/src/shell/forum_access_state.dart': (110, 1),
  'lib/src/shell/site_capabilities.dart': (82, 0),
  'lib/src/shell/composer/recipient_lookup.dart': (104, 0),
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
