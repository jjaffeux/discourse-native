import 'dart:async';

import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_composer.dart';
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
const _result = GifResult(
  title: 'Cat dance',
  url: 'https://media.example/cat.webp',
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

enum _Operation {
  unchanged,
  unchangedWhilePaging,
  failedReconnect,
  failedDisconnect,
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final operation in _Operation.values) {
    testWidgets(
      'loaded GIF ${operation.name} selection belongs to its opening session',
      (tester) async {
        final previousClient = debugNetworkImageHttpClientProvider;
        final images = FakeImageHttpClient(blankPng(width: 240, height: 180));
        debugNetworkImageHttpClientProvider = () => images;
        try {
          final site = instance('meta.discourse.org').copyWith(user: _user);
          final store = _FailingStore([site]);
          final api = _GifApi(
            paging: operation == _Operation.unchangedWhilePaging,
          );
          addTearDown(() {
            if (!api.pageResponse.isCompleted) api.pageResponse.complete();
          });
          await pumpShell(
            tester,
            defaultTargetPlatform == TargetPlatform.macOS ? desktop : phone,
            instances: [site],
            store: store,
            api: api,
            authenticator: FakeAuthenticator()..keys[_site] = 'key',
          );
          final shell = ShellScope.read(tester.element(primaryMainContent));
          await shell.chat.loadChannels(_site);
          expect(shell.openChatChannel(9), isTrue);
          await tester.pumpAndSettle();
          final composer = find.byType(ChatComposer);
          final composerState = tester.state(composer);
          await tester.tap(find.byKey(const ValueKey('chat-composer-add')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('chat-composer-gif')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('gif-category-0')));
          await tester.pumpAndSettle();
          final tile = find.byKey(const ValueKey('gif-result-0'));
          expect(tile, findsOneWidget);
          final pickerState = tester.state(find.byType(GifPicker));
          final lease = shell.chat.captureSession(_site);
          if (operation == _Operation.unchangedWhilePaging) {
            await tester.tap(
              find.byKey(const ValueKey('gif-picker-load-more')),
            );
            await tester.pump();
            expect(api.pagingStarted, isTrue);
            expect(
              tester
                  .widget<GifPicker>(find.byType(GifPicker))
                  .controller
                  .loadingMore,
              isTrue,
            );
            expect(tile, findsOneWidget);
          }
          final rollsBack =
              operation == _Operation.failedReconnect ||
              operation == _Operation.failedDisconnect;
          if (rollsBack) {
            store.failSignedOut = true;
            if (operation == _Operation.failedDisconnect) {
              expect(
                await tester.runAsync(() => shell.disconnectInstance(_site)),
                isFalse,
              );
            } else {
              await tester.runAsync(shell.connectCurrentInstance);
            }
            expect(shell.currentInstance?.user?.id, 1);
            expect(lease.isCurrent, isFalse);
            await shell.chat.loadChannels(_site);
            await shell.chat.openChannel(_site, 9, force: true);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.state(composer), same(composerState));
            expect(tester.state(find.byType(GifPicker)), same(pickerState));
            expect(shell.chat.canSendMessage(_site, 9), isTrue);
          }
          await tester.tap(tile);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          if (!rollsBack) {
            expect(api.chatMessagesSent.single.message, _result.markdown);
            expect(find.byType(GifPicker), findsNothing);
          } else {
            expect(api.chatMessagesSent, isEmpty);
            expect(find.byType(GifPicker), findsOneWidget);
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

class _GifApi extends FakeDiscourseApi {
  _GifApi({required bool paging})
    : super(
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
          FakeDiscourseApi.gifSearchKey('cats'): GifSearchPage(
            results: const [_result],
            nextPosition: paging ? 'next' : null,
          ),
        },
      );

  final pageResponse = Completer<void>();
  bool pagingStarted = false;

  @override
  Future<GifSearchPage> searchGifs({
    required String siteUrl,
    required String apiKey,
    required String query,
    required String fileDetail,
    String position = '0',
    String? clientId,
  }) async {
    if (position == 'next') {
      pagingStarted = true;
      await pageResponse.future;
    }
    return super.searchGifs(
      siteUrl: siteUrl,
      apiKey: apiKey,
      query: query,
      fileDetail: fileDetail,
      position: position,
      clientId: clientId,
    );
  }
}

class _FailingStore extends FakeInstanceStore {
  _FailingStore(super.instances);
  bool failSignedOut = false;

  @override
  Future<void> save(List<DiscourseInstance> instances) {
    if (failSignedOut && instances.any((site) => site.user == null)) {
      return Future.error(StateError('Account snapshot unavailable'));
    }
    return super.save(instances);
  }
}
