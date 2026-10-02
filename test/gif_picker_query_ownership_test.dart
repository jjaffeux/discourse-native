import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/gifs/gif.dart';
import 'package:discourse_native/src/plugins/gifs/gif_picker.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_settings.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/blank_png.dart';
import 'support/chat_shell.dart';
import 'support/fake_image_http_client.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _cat = GifResult(
  title: 'Cat dance',
  url: 'https://media.example/cat.webp',
  width: 240,
  height: 180,
);
const _dog = GifResult(
  title: 'Dog dance',
  url: 'https://media.example/dog.webp',
  width: 240,
  height: 180,
);
const _category = GifCategory(
  title: 'Cats',
  searchTerm: 'cats',
  imageUrl: 'https://media.example/cats.webp',
);
final _user = DiscourseUser(
  id: 1,
  username: 'staff',
  staff: true,
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);
const _channel = ChatChannel(
  id: 9,
  title: 'Support',
  kind: ChatChannelKind.category,
  membership: ChatMembership(following: true),
);

enum _Mutation { unchanged, newQuery, shortQuery, clear }

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final mutation in _Mutation.values) {
    testWidgets(
      'a GIF tile checks its current results after ${mutation.name} before repaint',
      (tester) async {
        final previousClient = debugNetworkImageHttpClientProvider;
        final images = FakeImageHttpClient(blankPng(width: 240, height: 180));
        debugNetworkImageHttpClientProvider = () => images;
        try {
          final api = _api();
          await pumpShell(
            tester,
            defaultTargetPlatform == TargetPlatform.macOS ? desktop : phone,
            instances: [instance('meta.discourse.org').copyWith(user: _user)],
            api: api,
            authenticator: FakeAuthenticator()..keys[_site] = 'key',
          );
          final shell = ShellScope.read(tester.element(primaryMainContent));
          await shell.chat.loadChannels(_site);
          expect(shell.openChatChannel(9), isTrue);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('chat-composer-add')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('chat-composer-gif')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('gif-category-0')));
          await tester.pumpAndSettle();
          final tile = find.byKey(const ValueKey('gif-result-0'));
          final controller = tester
              .widget<GifPicker>(find.byType(GifPicker))
              .controller;
          expect(controller.results, [_cat]);
          final search = find.byKey(const ValueKey('gif-picker-search'));
          if (mutation == _Mutation.clear) {
            await tester.tap(find.byKey(const ValueKey('gif-picker-clear')));
          } else {
            await tester.enterText(search, switch (mutation) {
              _Mutation.unchanged => 'cats',
              _Mutation.newQuery => 'dogs',
              _Mutation.shortQuery => 'ca',
              _Mutation.clear => '',
            });
          }
          // Input has already invalidated the results, but the previous frame
          // still paints its tile and can receive a tap before rebuilding.
          expect(
            controller.results,
            mutation == _Mutation.unchanged ? [_cat] : isEmpty,
          );
          expect(tile, findsOneWidget);
          await tester.tap(tile);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          if (mutation == _Mutation.unchanged) {
            expect(api.chatMessagesSent.single.message, _cat.markdown);
            expect(find.byType(GifPicker), findsNothing);
          } else {
            expect(api.chatMessagesSent, isEmpty);
            expect(find.byType(GifPicker), findsOneWidget);
            if (mutation == _Mutation.newQuery) {
              await tester.pump(const Duration(milliseconds: 700));
              await tester.pumpAndSettle();
            } else {
              await tester.tap(find.byKey(const ValueKey('gif-category-0')));
              await tester.pumpAndSettle();
            }
            final current = mutation == _Mutation.newQuery ? _dog : _cat;
            expect(controller.results, [current]);
            await tester.tap(tile);
            await tester.pumpAndSettle();
            expect(api.chatMessagesSent.single.message, current.markdown);
            expect(find.byType(GifPicker), findsNothing);
          }
          expect(tester.takeException(), isNull);
        } finally {
          debugNetworkImageHttpClientProvider = previousClient;
          PaintingBinding.instance.imageCache.clear();
        }
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
      }),
    );
  }
}

FakeDiscourseApi _api() => FakeDiscourseApi(
  user: _user,
  feeds: const {'/latest.json': []},
  siteConfigs: {
    _site: SiteConfig(
      plugins: PluginData.none.withValue(
        gifsSettingsDataKey,
        const GifsSettings(enabled: true),
      ),
    ),
  },
  chatChannelsBySite: const {
    _site: ChatChannels(public: [_channel], direct: []),
  },
  chatChannelsById: const {9: _channel},
  chatMessagesByKey: const {
    '9': (
      messages: [],
      canLoadMorePast: false,
      canLoadMoreFuture: false,
      targetMessageId: null,
    ),
  },
  gifCategoriesBySite: const {
    _site: [_category],
  },
  gifSearchPages: {
    FakeDiscourseApi.gifSearchKey('cats'): GifSearchPage(results: const [_cat]),
    FakeDiscourseApi.gifSearchKey('dogs'): GifSearchPage(results: const [_dog]),
  },
);
