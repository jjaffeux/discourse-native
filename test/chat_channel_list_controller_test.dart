import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/chat_channel_list_preferences.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_list_controller.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://one.example';
const _other = 'https://two.example';
const _channels = ChatChannelListSection.channels;
const _starred = ChatChannelListSection.starred;
const _dms = ChatChannelListSection.directMessages;

DiscourseUser _user({int id = 1, Map<String, dynamic>? options}) =>
    DiscourseUser(
      id: id,
      username: 'reader$id',
      plugins: PluginData.none.withValue(
        chatCurrentUserDataKey,
        ChatCurrentUser.fromCurrentUser({
          'user_option':
              options ??
              {
                for (final section in ChatChannelListSection.values) ...{
                  section.filterField: 'all',
                  section.sortField: section == _dms
                      ? 'priority'
                      : 'alphabetical',
                },
              },
        }),
      ),
    );

final class _Call {
  final started = Completer<void>();
  final result = Completer<UserPreferences>();
  late String siteUrl, username;
  late Map<String, Object?> values;
  late UserPreferences fallback;
  void succeed() => result.complete(fallback);
}

final class _Api extends FakeDiscourseApi {
  final calls = List.generate(8, (_) => _Call());
  int count = 0;
  @override
  Future<UserPreferences> updateUserPreferences({
    required String siteUrl,
    required String apiKey,
    required String username,
    required UserPreferences fallback,
    required Map<String, Object?> values,
    String? clientId,
  }) {
    final call = calls[count++];
    call.siteUrl = siteUrl;
    call.username = username;
    call.values = values;
    call.fallback = fallback;
    call.started.complete();
    return call.result.future;
  }
}

final class _Fixture {
  _Fixture({FakeApiCredentialReader? credentials}) {
    controller = ChatChannelListController(
      requests: FakePluginRequestHost(
        lifecycle: lifecycle,
        credentials:
            credentials ??
            (FakeApiCredentialReader()
              ..keys.addAll({_site: 'key', _other: 'key'})),
      ),
      currentUserFor: (site) => users[site],
      host: PluginUserOptionsHost(
        api: api,
        updateData: (site, field, update) {
          persisted++;
          users[site] = users[site]!.withPlugins(update(users[site]!.plugins));
        },
      ),
    );
    addTearDown(controller.dispose);
  }
  final users = {_site: _user(), _other: _user()};
  final lifecycle = SiteLifecycle();
  final api = _Api();
  int persisted = 0;
  late final ChatChannelListController controller;
}

final class _Credentials extends FakeApiCredentialReader {
  final gate = Completer<String?>();
  @override
  Future<String?> apiKeyFor(String siteUrl) => gate.future;
}

void main() {
  test(
    'concurrent field saves merge only their own results, preserving newer changes',
    () async {
      final f = _Fixture();
      final c = f.controller;
      final filter = c.setFilter(
        _site,
        _channels,
        ChatChannelListFilter.unread,
      );
      final sort = c.setSort(
        _site,
        _channels,
        ChatChannelListSort.recentActivity,
      );
      final starred = c.setFilter(
        _site,
        _starred,
        ChatChannelListFilter.mentions,
      );
      await Future.wait(f.api.calls.take(3).map((call) => call.started.future));
      expect(f.api.calls.take(3).map((call) => call.values), [
        {'chat_channel_list_filter': 'unread'},
        {'chat_channel_list_sort': 'recent_activity'},
        {'chat_channel_list_filter_starred': 'mentions'},
      ]);
      expect(
        c.preferencesFor(_site).sortFor(_channels),
        ChatChannelListSort.recentActivity,
      );
      expect(
        await c.setFilter(_site, _channels, ChatChannelListFilter.all),
        isFalse,
      );
      f.api.calls[1].succeed();
      expect(await sort, isTrue);
      final newerSort = c.setSort(
        _site,
        _channels,
        ChatChannelListSort.priority,
      );
      await f.api.calls[3].started.future;
      f.api.calls[3].succeed();
      expect(await newerSort, isTrue);
      f.api.calls[2].succeed();
      f.api.calls[0].succeed();
      expect(await Future.wait([filter, starred]), [true, true]);
      expect(c.preferencesFor(_site).wireValues, {
        'chat_channel_list_filter': 'unread',
        'chat_channel_list_sort': 'priority',
        'chat_channel_list_filter_starred': 'mentions',
        'chat_channel_list_sort_starred': 'alphabetical',
        'chat_channel_list_filter_dms': 'all',
        'chat_channel_list_sort_dms': 'priority',
      });
      expect(
        f.users[_site]!.chatCurrentUser!.channelListPreferences,
        c.preferencesFor(_site),
      );
      expect(
        c.preferencesFor(_other).filterFor(_channels),
        ChatChannelListFilter.all,
      );
    },
  );

  test(
    'failed filter restores its preference and bypass without rolling back a saved sort',
    () async {
      final f = _Fixture();
      f.users[_site] = _user(
        options: {
          _channels.filterField: 'unread',
          _channels.sortField: 'alphabetical',
        },
      );
      final c = f.controller;
      c.toggleFilter(_site, _channels);
      final filter = c.setFilter(
        _site,
        _channels,
        ChatChannelListFilter.mentions,
      );
      expect(c.bypassed(_site, _channels), isFalse);
      c.toggleFilter(_site, _channels);
      expect(c.bypassed(_site, _channels), isFalse);
      final sort = c.setSort(_site, _channels, ChatChannelListSort.priority);
      await Future.wait(f.api.calls.take(2).map((call) => call.started.future));
      f.api.calls[1].succeed();
      expect(await sort, isTrue);
      f.api.calls[0].result.completeError(StateError('offline'));
      expect(await filter, isFalse);
      expect(
        c.preferencesFor(_site).filterFor(_channels),
        ChatChannelListFilter.unread,
      );
      expect(
        c.preferencesFor(_site).sortFor(_channels),
        ChatChannelListSort.priority,
      );
      expect(c.bypassed(_site, _channels), isTrue);
      expect(
        c.errorFor(_site, _channels),
        'Could not save channel preferences. Try again.',
      );
      final retry = c.setFilter(
        _site,
        _channels,
        ChatChannelListFilter.mentions,
      );
      await f.api.calls[2].started.future;
      f.api.calls[2].succeed();
      expect(await retry, isTrue);
      expect(c.errorFor(_site, _channels), isNull);
      expect(c.bypassed(_site, _channels), isFalse);
    },
  );

  test('failed sort leaves the active filter and bypass intact', () async {
    final f = _Fixture();
    f.users[_site] = _user(
      options: {
        _channels.filterField: 'unread',
        _channels.sortField: 'alphabetical',
      },
    );
    f.controller.toggleFilter(_site, _channels);
    final save = f.controller.setSort(
      _site,
      _channels,
      ChatChannelListSort.priority,
    );
    await f.api.calls[0].started.future;
    f.api.calls[0].result.completeError(StateError('offline'));
    expect(await save, isFalse);
    expect(
      f.controller.preferencesFor(_site).sortFor(_channels),
      ChatChannelListSort.alphabetical,
    );
    expect(
      f.controller.preferencesFor(_site).filterFor(_channels),
      ChatChannelListFilter.unread,
    );
    expect(f.controller.bypassed(_site, _channels), isTrue);
    expect(f.persisted, 0);
  });

  test(
    'show all is section-local and transient, preserving sort and stored options',
    () async {
      final f = _Fixture();
      f.users[_site] = _user(
        options: {
          _channels.filterField: 'unread',
          _channels.sortField: 'recent_activity',
          _starred.filterField: 'mentions',
          _starred.sortField: 'priority',
        },
      );
      final c = f.controller;
      c.toggleFilter(_site, _channels);
      expect(c.bypassed(_site, _channels), isTrue);
      expect(c.bypassed(_site, _starred), isFalse);
      expect(
        c.preferencesFor(_site).filterFor(_channels),
        ChatChannelListFilter.unread,
      );
      expect(
        c.preferencesFor(_site).sortFor(_channels),
        ChatChannelListSort.recentActivity,
      );
      expect(
        await c.setFilter(_site, _channels, ChatChannelListFilter.unread),
        isTrue,
      );
      expect(c.bypassed(_site, _channels), isFalse);
      c.toggleFilter(_site, _channels);
      c.forget(_site);
      expect(c.bypassed(_site, _channels), isFalse);
      expect(f.api.count, 0);
      expect(f.persisted, 0);
    },
  );

  for (final fails in [false, true]) {
    test(
      'late ${fails ? 'failure' : 'success'} cannot change a replacement account',
      () async {
        final f = _Fixture();
        final saving = f.controller.setFilter(
          _site,
          _channels,
          ChatChannelListFilter.unread,
        );
        await f.api.calls[0].started.future;
        f.lifecycle.invalidate(_site);
        f.controller.forget(_site);
        f.users[_site] = _user(id: 2);
        final replacement = f.controller.setSort(
          _site,
          _channels,
          ChatChannelListSort.priority,
        );
        await f.api.calls[1].started.future;
        if (fails) {
          f.api.calls[0].result.completeError(StateError('old failure'));
        } else {
          f.api.calls[0].succeed();
        }
        expect(await saving, isFalse);
        expect(
          f.controller.preferencesFor(_site).filterFor(_channels),
          ChatChannelListFilter.all,
        );
        expect(f.controller.saving(_site, _channels.sortField), isTrue);
        f.api.calls[1].succeed();
        expect(await replacement, isTrue);
        expect(f.api.calls.take(2).map((call) => call.username), [
          'reader1',
          'reader2',
        ]);
        expect(f.persisted, 1);
      },
    );
  }

  test(
    'switching sites keeps independent in-flight saves and bypass state',
    () async {
      final f = _Fixture();
      final first = f.controller.setFilter(
        _site,
        _dms,
        ChatChannelListFilter.unread,
      );
      final second = f.controller.setFilter(
        _other,
        _dms,
        ChatChannelListFilter.mentions,
      );
      await Future.wait(f.api.calls.take(2).map((call) => call.started.future));
      f.api.calls[1].succeed();
      expect(await second, isTrue);
      f.controller.toggleFilter(_other, _dms);
      f.api.calls[0].succeed();
      expect(await first, isTrue);
      expect(f.controller.bypassed(_site, _dms), isFalse);
      expect(f.controller.bypassed(_other, _dms), isTrue);
      expect(f.api.calls.take(2).map((call) => call.siteUrl), [_site, _other]);
    },
  );

  test(
    'session account changes retire writes even when the first user returns',
    () async {
      final f = _Fixture();
      final firstUser = f.users[_site]!;
      final save = f.controller.setFilter(
        _site,
        _channels,
        ChatChannelListFilter.unread,
      );
      await f.api.calls[0].started.future;
      f.users[_site] = _user(id: 2);
      f.controller.refresh(_site);
      f.users[_site] = firstUser;
      f.controller.refresh(_site);
      f.api.calls[0].succeed();
      expect(await save, isFalse);
      expect(f.persisted, 0);
      expect(f.controller.saving(_site, _channels.filterField), isFalse);
      expect(
        f.controller.preferencesFor(_site).filterFor(_channels),
        ChatChannelListFilter.all,
      );
    },
  );

  test(
    'credential response after account invalidation never sends a write',
    () async {
      final credentials = _Credentials();
      final f = _Fixture(credentials: credentials);
      final save = f.controller.setFilter(
        _site,
        _channels,
        ChatChannelListFilter.unread,
      );
      f.lifecycle.invalidate(_site);
      f.controller.forget(_site);
      f.users[_site] = _user(id: 2);
      credentials.gate.complete('old-key');
      expect(await save, isFalse);
      expect(f.api.count, 0);
    },
  );

  test(
    'older and partially upgraded servers never receive unsupported fields',
    () async {
      final f = _Fixture();
      f.users[_site] = _user(options: {});
      for (final section in ChatChannelListSection.values) {
        expect(
          await f.controller.setFilter(
            _site,
            section,
            ChatChannelListFilter.unread,
          ),
          isFalse,
        );
        expect(
          await f.controller.setSort(
            _site,
            section,
            ChatChannelListSort.priority,
          ),
          isFalse,
        );
      }
      f.users[_site] = _user(options: {_channels.filterField: 'all'});
      expect(
        await f.controller.setSort(
          _site,
          _channels,
          ChatChannelListSort.priority,
        ),
        isFalse,
      );
      expect(f.api.count, 0);
    },
  );

  test('fresh session options are accepted after a completed write', () async {
    final f = _Fixture();
    final stale = f.users[_site]!;
    final save = f.controller.setFilter(
      _site,
      _channels,
      ChatChannelListFilter.mentions,
    );
    await f.api.calls[0].started.future;
    f.api.calls[0].succeed();
    expect(await save, isTrue);
    f.users[_site] = stale;
    expect(
      f.controller.preferencesFor(_site).filterFor(_channels),
      ChatChannelListFilter.all,
    );
  });
}
