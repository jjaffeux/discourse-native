import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/shell/composer/autocomplete.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('composer shows canonical emoji before optional aliases arrive', (
    tester,
  ) async {
    final api = _EmojiApi();
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);
    await shell.ensureEmojiCatalog(_site);
    final composer = _openReply(shell);
    composer.text.value = const TextEditingValue(
      text: ':che',
      selection: TextSelection.collapsed(offset: 4),
    );
    await tester.pump(ComposerAutocomplete.debounce);
    await tester.pump();

    expect(api.aliasRequests, 1);
    expect(api.aliases.isCompleted, isFalse);
    expect(_codes(composer), ['cheese']);
    expect(
      composer.autocomplete.canAccept(composer.autocomplete.suggestions.first),
      isTrue,
    );

    api.aliases.complete(const {
      'smile': ['cheerful'],
    });
    await tester.pump();
    await tester.pump();
    expect(_codes(composer), containsAll(['cheese', 'smile']));
    expect(api.aliasRequests, 1);
    shell.closeComposer(composer: composer);
  });

  testWidgets('alias arrival enriches the current emoji query only', (
    tester,
  ) async {
    final api = _EmojiApi();
    final shell = await _loadShell(api);
    addTearDown(shell.dispose);
    await shell.ensureEmojiCatalog(_site);
    final composer = _openReply(shell);
    composer.text.value = const TextEditingValue(
      text: ':che',
      selection: TextSelection.collapsed(offset: 4),
    );
    await tester.pump(ComposerAutocomplete.debounce);
    composer.text.value = const TextEditingValue(
      text: ':smi',
      selection: TextSelection.collapsed(offset: 4),
    );
    await tester.pump(ComposerAutocomplete.debounce);
    api.aliases.complete(const {
      'cheese': ['cheerful'],
    });
    await tester.pump();
    await tester.pump();

    expect(_codes(composer), ['smile']);
    expect(composer.autocomplete.query, 'smi');
    shell.closeComposer(composer: composer);
  });

  testWidgets(
    'failed aliases retain canonical emoji and the chosen skin tone',
    (tester) async {
      final api = _EmojiApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      await shell.ensureEmojiCatalog(_site);
      await shell.emojiPickerStore.writeSkinTone(
        siteUrl: _site,
        tone: EmojiSkinTone.t4,
      );
      final composer = _openReply(shell);
      composer.text.value = const TextEditingValue(
        text: ':wa',
        selection: TextSelection.collapsed(offset: 3),
      );
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();
      expect(_codes(composer), ['wave:t4']);

      api.aliases.completeError(StateError('offline'));
      await tester.pump();
      await tester.pump();
      expect(_codes(composer), ['wave:t4']);
      expect(composer.autocomplete.hasError, isFalse);
      expect(api.aliasRequests, 1);
      shell.closeComposer(composer: composer);
    },
  );
}

List<String> _codes(ComposerController composer) => composer
    .autocomplete
    .suggestions
    .where((suggestion) => suggestion.action == null)
    .map((suggestion) => suggestion.value)
    .toList();

Future<ShellController> _loadShell(_EmojiApi api) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    ownsApi: false,
  );
  await shell.load();
  return shell;
}

ComposerController _openReply(ShellController shell) {
  shell.store.put(
    _site,
    const TopicDetail(id: 7, title: 'Topic', stream: [], canCreatePost: true),
  );
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'topic', title: 'Topic'),
  );
  shell.openReply();
  return shell.visibleComposer!;
}

class _EmojiApi extends FakeDiscourseApi {
  _EmojiApi() : super(user: _user, feeds: const {'/latest.json': []});

  final aliases = Completer<Map<String, List<String>>>();
  int aliasRequests = 0;

  @override
  Future<SiteEmojiCatalog> emojiCatalog({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async => SiteEmojiCatalog(
    groups: [
      SiteEmojiGroup(
        id: 'all',
        emojis: const [
          SiteEmoji(name: 'cheese', url: 'https://cdn.example/cheese.png'),
          SiteEmoji(name: 'smile', url: 'https://cdn.example/smile.png'),
          SiteEmoji(
            name: 'wave',
            url: 'https://cdn.example/wave.png',
            tonable: true,
          ),
        ],
      ),
    ],
  );

  @override
  Future<Map<String, List<String>>> emojiSearchAliases({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) {
    aliasRequests++;
    return aliases.future;
  }
}
