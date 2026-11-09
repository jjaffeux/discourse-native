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

  const chatDataLayer = {
    'lib/src/plugins/chat/chat_api.dart',
    'lib/src/plugins/chat/chat_bookmark.dart',
    'lib/src/plugins/chat/chat_channel.dart',
    'lib/src/plugins/chat/chat_conversation_contract.dart',
    'lib/src/plugins/chat/chat_message.dart',
    'lib/src/plugins/chat/chat_message_contract.dart',
    'lib/src/plugins/chat/chat_message_timeline.dart',
    'lib/src/plugins/chat/chat_pin.dart',
    'lib/src/plugins/chat/chat_search.dart',
    'lib/src/plugins/chat/chat_thread.dart',
    'lib/src/plugins/chat/chat_time.dart',
  };

  test('chat models and wire contracts reach no controller or service key', () {
    const forbidden = {
      'lib/src/plugins/chat/chat_controller.dart',
      'lib/src/plugins/chat/chat_services.dart',
    };
    expect(graph.edges.keys.toSet().intersection(forbidden), forbidden);
    expect({
      for (final library in chatDataLayer)
        if (graph.closureOf(library).intersection(forbidden) case final reached
            when reached.isNotEmpty)
          library: reached,
    }, isEmpty);
  });

  test('chat data layer libraries participate in no import cycle', () {
    expect(graph.edges.keys.toSet().intersection(chatDataLayer), chatDataLayer);
    expect(librariesInCycles().intersection(chatDataLayer), isEmpty);
  });
}
