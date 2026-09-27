import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _continuation =
    'Continue the discussion from [A real topic](https://meta.discourse.org/t/a-real-topic/7)';
const _savedMessage = ComposerDraft(
  action: ComposerDraft.privateMessageAction,
  title: 'An unrelated message',
  reply: 'An unrelated saved message',
  recipients: 'someone',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDraftStore drafts;
  late FakeDiscourseApi api;

  TopicDetail source({
    bool canReplyAsNewTopic = true,
    bool privateMessage = false,
    List<String> allowedMessageUsers = const [],
    List<String> allowedMessageGroups = const [],
  }) => TopicDetail(
    id: 7,
    title: 'A real topic',
    stream: const [1],
    categoryId: privateMessage ? null : 5,
    canCreatePost: true,
    canReplyAsNewTopic: canReplyAsNewTopic,
    privateMessage: privateMessage,
    allowedMessageUsers: allowedMessageUsers,
    allowedMessageGroups: allowedMessageGroups,
  );

  Future<ShellController> shell({
    bool canReplyAsNewTopic = true,
    bool privateMessage = false,
    bool canSendPrivateMessages = true,
    List<String> allowedMessageUsers = const [],
    List<String> allowedMessageGroups = const [],
  }) async {
    drafts = FakeDraftStore();
    await drafts.write(
      _siteUrl,
      'new_topic',
      const ComposerDraft(reply: 'An unrelated saved topic').encode(),
    );
    await drafts.write(_siteUrl, 'new_private_message', _savedMessage.encode());
    final reader = DiscourseUser(
      id: 1,
      username: 'reader',
      canSendPrivateMessages: canSendPrivateMessages,
    );
    api = FakeDiscourseApi(
      user: reader,
      feeds: const {'/latest.json': <Topic>[]},
      categoryList: const [
        TopicCategory(
          id: 5,
          name: 'Support',
          color: '0088CC',
          permission: 1,
          minimumRequiredTags: 1,
        ),
      ],
    );
    final controller = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: reader),
      ]),
      api: api,
      authenticator: FakeAuthenticator()..keys[_siteUrl] = 'api-key',
      drafts: drafts,
      trackers: FakeSiteTracker.reset(),
    );
    await controller.load();
    await pumpEventQueue();
    controller.store.put(
      _siteUrl,
      source(
        canReplyAsNewTopic: canReplyAsNewTopic,
        privateMessage: privateMessage,
        allowedMessageUsers: allowedMessageUsers,
        allowedMessageGroups: allowedMessageGroups,
      ),
    );
    controller.store.put(
      _siteUrl,
      const Post(
        id: 1,
        postNumber: 1,
        username: 'sam',
        cooked: '<p>First post</p>',
      ),
    );
    controller.pushContent(
      ContentRoute.topic(
        topicId: 7,
        slug: 'a-real-topic',
        title: 'A real topic',
      ),
    );
    return controller;
  }

  test('opens a category-aware new-topic composer over its source', () async {
    final controller = await shell(canReplyAsNewTopic: true);
    addTearDown(controller.dispose);

    await controller.openReplyAsNewTopic(_continuation);

    final composer = controller.visibleComposer;
    expect(composer, isNotNull);
    expect(composer!.target.isNewTopic, isTrue);
    expect(composer.target.originTopicId, 7);
    expect(composer.target.targetRecipients, isNull);
    expect(composer.categoryId, 5);
    expect(composer.canSubmit, isFalse);
    expect(composer.raw, _continuation);
  });

  test('does nothing when the topic guardian withholds the action', () async {
    final controller = await shell(canReplyAsNewTopic: false);
    addTearDown(controller.dispose);

    await controller.openReplyAsNewTopic('Continue elsewhere');

    expect(controller.visibleComposer, isNull);
  });

  test(
    'continues a message among its own participants, not in public',
    () async {
      final controller = await shell(
        privateMessage: true,
        allowedMessageUsers: const ['sam', 'reader', 'alice'],
        allowedMessageGroups: const ['moderators'],
      );
      addTearDown(controller.dispose);
      expect(controller.canReplyAsNewTopic(controller.currentTopic!), isTrue);

      await controller.openReplyAsNewTopic(_continuation);

      final composer = controller.visibleComposer!;
      expect(composer.target.isPrivateMessage, isTrue);
      expect(composer.target.isNewTopic, isFalse);
      expect(composer.target.targetRecipients, 'sam,alice,moderators');
      expect(composer.target.originTopicId, 7);
      expect(composer.categoryId, isNull);
      expect(composer.raw, _continuation);

      // The shared new-message draft is neither restored nor overwritten.
      expect(
        composer.target.draftKey,
        startsWith('${ComposerDraft.newPrivateMessageDraftKey}_'),
      );
      await composer.flushDraft();
      expect(
        drafts.saved['$_siteUrl::${ComposerDraft.newPrivateMessageDraftKey}'],
        _savedMessage.encode(),
      );
      expect(api.draftsSaved, isNotEmpty);
      expect(
        api.draftsSaved.map((save) => save['draftKey']),
        everyElement(composer.target.draftKey),
      );
    },
  );

  test('names the author when a message has no one else left in it', () async {
    final controller = await shell(
      privateMessage: true,
      allowedMessageUsers: const ['reader'],
    );
    addTearDown(controller.dispose);

    await controller.openReplyAsNewTopic(_continuation);

    expect(controller.visibleComposer!.target.targetRecipients, 'reader');
  });

  test('withholds a message continuation from a user who cannot send '
      'messages', () async {
    final controller = await shell(
      privateMessage: true,
      canSendPrivateMessages: false,
      allowedMessageUsers: const ['sam', 'reader'],
    );
    addTearDown(controller.dispose);
    expect(controller.canReplyAsNewTopic(controller.currentTopic!), isFalse);

    await controller.openReplyAsNewTopic(_continuation);

    expect(controller.visibleComposer, isNull);
  });

  test('a topic turned into a message while its composer is replaced opens '
      'nothing', () async {
    final controller = await shell();
    addTearDown(controller.dispose);
    controller.openReply();
    final existing = controller.visibleComposer!;
    await controller.finishComposerDraftRestore(existing);
    existing.text.text = 'An unsent reply';
    controller.confirmComposerReplacement = (composer) async {
      controller.store.put(
        _siteUrl,
        source(privateMessage: true, allowedMessageUsers: const ['sam']),
      );
      controller.closeComposer(composer: composer);
    };

    await controller.openReplyAsNewTopic(_continuation);

    expect(controller.visibleComposer, isNull);
  });
}
