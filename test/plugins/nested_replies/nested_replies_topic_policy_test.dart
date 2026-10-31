import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an unrelated partial payload preserves established topic policy', () {
    const registry = PluginRegistry([NestedRepliesPlugin()]);
    final held = Topic.fromJson(
      const {'id': 7, 'is_nested_view': true, 'has_new_replies': true},
      const {},
      'https://reader.example',
      extensions: registry,
    );
    final partial = Topic.fromJson(
      const {'id': 7, 'title': 'updated title'},
      const {},
      'https://reader.example',
      extensions: registry,
      context: const TopicRecordDecodeContext.partial(),
    );
    final result = held.merge(partial);
    expect(result.readingPolicy.allowsChronologicalResume, isFalse);
    expect(result.showNewRepliesDot, isTrue);
  });
}
