import 'package:flutter_test/flutter_test.dart';

import '../tool/architecture_graph.dart';

void main() {
  final graph = LibraryGraph.load();

  Set<String> librariesInCycles() => graph.cycles().expand((c) => c).toSet();

  test('the leaf plugin and kit libraries participate in no import cycle', () {
    const leaves = {
      'lib/src/plugins/discourse_ai/ai_conversations_page.dart',
      'lib/src/plugins/discourse_ai/ai_conversations_plugin.dart',
      'lib/src/plugins/discourse_ai/ai_conversations_service.dart',
      'lib/src/plugins/discourse_ai/ai_conversations_session.dart',
      'lib/src/plugins/discourse_events/event_card.dart',
      'lib/src/plugins/discourse_events/event_participants.dart',
      'lib/src/plugins/gamification/gamification_controller.dart',
      'lib/src/plugins/gamification/gamification_navigation.dart',
      'lib/src/ui/components/d_card.dart',
      'lib/src/ui/components/d_header_morph.dart',
      'lib/src/ui/components/d_item.dart',
      'lib/src/ui/components/d_page_surface.dart',
      'lib/src/ui/components/d_sheet.dart',
    };
    expect(graph.edges.keys.toSet().intersection(leaves), leaves);
    expect(librariesInCycles().intersection(leaves), isEmpty);
  });
}
