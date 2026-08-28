import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('group message guardians survive the current-user snapshot', () {
    const models = DiscourseModelCodec.core();
    final live = models.currentUser(const {
      'id': 7,
      'username': 'sam',
      'admin': true,
      'can_send_private_messages': true,
    }, 'https://forum.example');

    expect(live.admin, isTrue);
    expect(live.canSendPrivateMessages, isTrue);

    final stored = DiscourseUser.fromJson(live.toJson());
    expect(stored.admin, isTrue);
    expect(stored.canSendPrivateMessages, isTrue);
  });
}
