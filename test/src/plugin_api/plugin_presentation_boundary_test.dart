import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_plugin.dart';
import 'package:discourse_native/src/plugins/voice/voice_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Reactions alone contributes its wire type to the core Likes feed', () {
    final core = PluginRegistry.validated(const []);
    final extended = PluginRegistry.validated(const [ReactionsPlugin()]);
    expect(core.likeNotificationTypes, userMenuLikeNotificationTypes);
    expect(
      core.likeNotificationTypes,
      isNot(contains(const NotificationTypeName('reaction'))),
    );
    expect(extended.likeNotificationTypes, [
      ...userMenuLikeNotificationTypes,
      const NotificationTypeName('reaction'),
    ]);
  });

  test(
    'Voice owns transcript recognition and core treats its key as opaque',
    () {
      const draft = UserDraft(
        key: 'new_topic_voice_7_1234',
        sequence: 1,
        data: ComposerDraft(
          action: ComposerDraft.createTopicAction,
          reply: 'Transcript',
        ),
      );
      expect(PluginRegistry.empty.draftPresentation(draft), isNull);
      expect(draft.isNewTopic, isTrue);
      final presentation = const PluginRegistry([
        VoicePlugin(),
      ]).draftPresentation(draft)!;
      expect(presentation.label, 'Call transcript draft');
      expect(presentation.icon, DIcons.closedCaptioning);
    },
  );
}
