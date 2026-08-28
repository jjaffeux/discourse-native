import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/assign/assign_plugin.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Assign owns notification decoding, route, wording and icon', () {
    const registry = PluginRegistry([AssignPlugin()]);
    final notification = DiscourseNotification.fromJson(const {
      'id': 1,
      'notification_type': 34,
      'topic_id': 12,
      'post_number': 4,
      'slug': 'work-list',
      'data': {'display_username': 'sam', 'topic_title': 'Work list'},
    });

    final resolved = registry.resolveNotification(notification);

    expect(resolved.presentation.actor, 'sam');
    expect(resolved.presentation.phrase, 'assigned Work list to you');
    expect(resolved.presentation.icon, DIcons.userPlus);
    expect(resolved.path, '/t/work-list/12/4');
  });
}
