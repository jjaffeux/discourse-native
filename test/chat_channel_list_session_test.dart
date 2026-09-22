import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_list_preferences.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

final class _SessionApi extends FakeDiscourseApi {
  final started = Completer<void>();
  final response = Completer<DiscourseUser>();
  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) {
    if (!started.isCompleted) started.complete();
    return response.future;
  }
}

void main() {
  test(
    'a late session snapshot preserves committed options in warm storage and refreshes unrelated data',
    () async {
      final options = ChatChannelListPreferences.read(const {
        'chat_channel_list_filter': 'all',
        'chat_channel_list_sort': 'alphabetical',
      });
      final user = DiscourseUser(
        id: 7,
        username: 'reader',
        plugins: PluginData.none.withValue(
          chatCurrentUserDataKey,
          ChatCurrentUser(channelListPreferences: options),
        ),
      );
      final api = _SessionApi();
      final store = FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: user),
      ]);
      final shell = ShellController(
        plugins: installedPlugins,
        instanceStore: store,
        api: api,
        authenticator: FakeAuthenticator()..keys[_site] = 'key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      await api.started.future;
      final controller = shell.pluginSession
          .require(chatControllerService)
          .channelListPreferences;
      expect(
        await controller.setFilter(
          _site,
          ChatChannelListSection.channels,
          ChatChannelListFilter.unread,
        ),
        isTrue,
      );
      expect(
        await controller.setSort(
          _site,
          ChatChannelListSection.channels,
          ChatChannelListSort.priority,
        ),
        isTrue,
      );
      final accepted = Completer<void>();
      void observe() {
        if (shell.currentInstance?.user?.name == 'Fresh name' &&
            !accepted.isCompleted) {
          accepted.complete();
        }
      }

      shell.addListener(observe);
      addTearDown(() => shell.removeListener(observe));
      api.response.complete(
        DiscourseUser(
          id: 7,
          username: 'reader',
          name: 'Fresh name',
          plugins: user.plugins,
        ),
      );
      await accepted.future;
      final persisted = (await store.load()).single.user!;
      expect(persisted.name, 'Fresh name');
      expect(persisted.chatCurrentUser!.channelListPreferences.wireValues, {
        'chat_channel_list_filter': 'unread',
        'chat_channel_list_sort': 'priority',
      });
      expect(
        controller.preferencesFor(_site),
        persisted.chatCurrentUser!.channelListPreferences,
      );
    },
  );
}
