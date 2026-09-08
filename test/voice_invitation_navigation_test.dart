import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/voice/voice_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_controller.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_shell_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/voice_fake_chat_conversations.dart';

const _firstSite = PluginRouteSite(
  url: 'https://one.example',
  title: 'One',
  isConnected: true,
);
const _secondSite = PluginRouteSite(
  url: 'https://two.example/forum',
  title: 'Two',
  isConnected: true,
);
const _room = <String, dynamic>{
  'id': 7,
  'name': 'Watercooler',
  'slug': 'watercooler',
  'public': true,
  'room_type': 'open',
};
const _invitation = '/voice/r/watercooler/invited-by/Older';
const _newInvitation = '/voice/r/watercooler/invited-by/Newer';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final boundary in ['directory', 'room']) {
    test('a forum switch during $boundary loading retires the link', () async {
      final harness = _Harness();
      final response = harness.hold(boundary);
      final opening = harness.shell.openPluginUrl(_invitation);
      await response.started.future;

      harness.host.selectInstance(1);
      final destination = harness.host.currentContent;
      response.release();

      expect(await opening, isTrue);
      expect(harness.host.currentSite?.url, _secondSite.url);
      expect(harness.host.currentContent, same(destination));
      expect(harness.host.pushed, isEmpty);
      if (boundary == 'directory') {
        expect(harness.transport.reads.map((read) => read.path), [
          '/voice/rooms.json',
        ]);
      }
      expect(await harness.inviterOnNextJoin(), isNull);
    });

    test('new content during $boundary loading retires the link', () async {
      final harness = _Harness();
      final response = harness.hold(boundary);
      final opening = harness.shell.openPluginUrl(_invitation);
      await response.started.future;

      harness.host.pushContent(
        const ContentRoute(
          id: 'bookmarks',
          title: 'Bookmarks',
          icon: DIcons.bookmark,
        ),
      );
      response.release();

      expect(await opening, isTrue);
      expect(harness.host.currentContent?.id, 'bookmarks');
      expect(harness.host.pushed, hasLength(1));
      expect(await harness.inviterOnNextJoin(), isNull);
    });

    test(
      'replacing the same route during $boundary loading retires the link',
      () async {
        final harness = _Harness();
        final response = harness.hold(boundary);
        final opening = harness.shell.openPluginUrl(_invitation);
        await response.started.future;

        final current = harness.host.currentContent!;
        final replacement = ContentRoute(
          id: current.id,
          title: current.title,
          icon: current.icon,
        );
        harness.host.replaceCurrentContent(replacement);
        response.release();

        expect(await opening, isTrue);
        expect(harness.host.currentContent, same(replacement));
        expect(harness.host.pushed, isEmpty);
        expect(await harness.inviterOnNextJoin(), isNull);
      },
    );

    for (final newerCompletesFirst in [false, true]) {
      test(
        'the newer invitation owns attribution while $boundary is pending '
        '(${newerCompletesFirst ? 'newer' : 'older'} completes first)',
        () async {
          final harness = _Harness();
          final olderResponse = harness.hold(boundary);
          final older = harness.shell.openPluginUrl(_invitation);
          await olderResponse.started.future;

          final newerResponse = harness.hold('room');
          final newer = harness.shell.openPluginUrl(_newInvitation);
          await newerResponse.started.future;

          if (newerCompletesFirst) {
            newerResponse.release();
            expect(await newer, isTrue);
            olderResponse.release();
            expect(await older, isTrue);
          } else {
            olderResponse.release();
            expect(await older, isTrue);
            expect(harness.host.pushed, isEmpty);
            // A retired link must not stash its attribution before the new
            // invitation has resolved and taken the reader to the room.
            expect(await harness.inviterOnNextJoin(), isNull);
            newerResponse.release();
            expect(await newer, isTrue);
          }

          expect(harness.host.pushed, hasLength(1));
          expect(harness.host.currentContent?.id, 'voice-room-7');
          expect(await harness.inviterOnNextJoin(), 'newer');
        },
      );
    }

    for (final retirement in [
      'controller',
      'account',
      'removal',
      'disconnect',
    ]) {
      test('$retirement during $boundary loading retires the link', () async {
        final harness = _Harness();
        final response = harness.hold(boundary);
        final opening = harness.shell.openPluginUrl(_invitation);
        await response.started.future;

        switch (retirement) {
          case 'controller':
            harness.controller.forget(_firstSite.url);
          case 'account':
            // Same URL, user and connected state; only the account lease
            // reveals that credentials have been retired and replaced.
            harness.requests.forget(_firstSite.url);
            harness.requests.apiKeys[_firstSite.url] = 'replacement-key';
          case 'removal':
            harness.host.sites.removeAt(0);
          case 'disconnect':
            harness.host.sites[0] = PluginRouteSite(
              url: _firstSite.url,
              title: _firstSite.title,
              isConnected: false,
            );
        }
        response.release();

        expect(await opening, isTrue);
        expect(harness.host.pushed, isEmpty);
        if (boundary == 'directory') {
          expect(harness.transport.reads, hasLength(1));
        }
        expect(await harness.inviterOnNextJoin(), isNull);
      });
    }

    test(
      'controller close during $boundary loading handles cancellation',
      () async {
        final harness = _Harness();
        final response = harness.hold(boundary);
        final opening = harness.shell.openPluginUrl(_invitation);
        await response.started.future;

        await harness.controller.close();
        response.release();

        expect(await opening, isTrue);
        expect(harness.host.pushed, isEmpty);
      },
    );
  }

  test(
    'selection callbacks cannot change the captured target by reordering sites',
    () async {
      final harness = _Harness();
      harness.host.onSelect = () {
        harness.host.sites
          ..clear()
          ..addAll([_secondSite, _firstSite]);
      };

      expect(
        await harness.shell.openPluginUrl('${_secondSite.url}$_invitation'),
        isTrue,
      );

      expect(harness.host.currentSite?.url, _secondSite.url);
      expect(harness.host.pushed.single.siteUrl, _secondSite.url);
      expect(harness.host.currentContent?.id, 'voice-room-7');
      expect(harness.transport.reads.map((read) => read.siteUrl), [
        _secondSite.url,
        _secondSite.url,
      ]);
      expect(
        await harness.inviterOnNextJoin(siteUrl: _secondSite.url),
        'older',
      );
    },
  );

  test(
    'removal during site selection handles the link without loading',
    () async {
      final harness = _Harness();
      harness.host.onSelect = () => harness.host.sites.removeLast();

      expect(
        await harness.shell.openPluginUrl('${_secondSite.url}$_invitation'),
        isTrue,
      );

      expect(harness.transport.reads, isEmpty);
      expect(harness.host.pushed, isEmpty);
    },
  );

  test('a newer invitation in a selection callback takes ownership', () async {
    final harness = _Harness();
    late Future<bool> newer;
    harness.host.onSelect = () {
      newer = harness.shell.openPluginUrl('${_secondSite.url}$_newInvitation');
    };

    final older = harness.shell.openPluginUrl('${_secondSite.url}$_invitation');
    expect(await older, isTrue);
    expect(await newer, isTrue);

    expect(harness.host.pushed, hasLength(1));
    expect(harness.host.pushed.single.siteUrl, _secondSite.url);
    expect(await harness.inviterOnNextJoin(siteUrl: _secondSite.url), 'newer');
  });

  test('an unhandled URL does not retire the pending invitation', () async {
    final harness = _Harness();
    final response = harness.hold('room');
    final opening = harness.shell.openPluginUrl(_invitation);
    await response.started.future;

    expect(await harness.shell.openPluginUrl('/latest'), isFalse);
    response.release();

    expect(await opening, isTrue);
    expect(harness.host.pushed, hasLength(1));
    expect(await harness.inviterOnNextJoin(), 'older');
  });

  test('a newer missing room still retires the pending invitation', () async {
    final harness = _Harness();
    final response = harness.hold('room');
    final opening = harness.shell.openPluginUrl(_invitation);
    await response.started.future;
    harness.transport.failures['GET /voice/rooms/missing.json'] =
        const SiteLookupException(SiteLookupFailure.notDiscourse, 'missing');

    expect(await harness.shell.openPluginUrl('/voice/r/missing'), isFalse);
    response.release();

    expect(await opening, isTrue);
    expect(harness.host.pushed, isEmpty);
    expect(await harness.inviterOnNextJoin(), isNull);
  });
}

final class _HeldResponse {
  _HeldResponse(this.body);

  final Map<String, dynamic> body;
  final started = Completer<void>();
  final _response = Completer<Map<String, dynamic>>();

  Future<Map<String, dynamic>> respond(PluginTransportRequest _) {
    started.complete();
    return _response.future;
  }

  void release() {
    if (!_response.isCompleted) _response.complete(body);
  }
}

final class _Harness {
  _Harness() {
    controller = VoiceController(
      api: VoiceApi(transport),
      chatConversations: FakeChatConversationCapability(),
      requests: requests,
      trackerFor: (_) => null,
      userIdFor: (_) => 1,
      onCallSiteChanged: () {},
    );
    shell = VoiceShellService(
      controller: controller,
      host: host,
      recordingEnabled: (_) => false,
    );
    addTearDown(controller.close);
  }

  final host = _RouteHost();
  final requests = PluginTestRequestHost(
    apiKeys: {_firstSite.url: 'key-one', _secondSite.url: 'key-two'},
  );
  final transport = RecordingPluginTransport(
    responses: const {
      'GET /voice/rooms.json': {'rooms': <Object?>[]},
      'GET /voice/rooms/watercooler.json': _room,
    },
    responders: {
      // Observe invitation attribution through the real join request. A
      // server refusal keeps these navigation tests out of native media.
      'POST /voice/rooms/7/join.json': (_) =>
          throw const WriteException(WriteFailure.forbidden),
    },
  );
  late final VoiceController controller;
  late final VoiceShellService shell;

  _HeldResponse hold(String boundary) {
    final path = boundary == 'directory'
        ? '/voice/rooms.json'
        : '/voice/rooms/watercooler.json';
    final response = _HeldResponse(transport.responses['GET $path']!);
    addTearDown(response.release);
    transport.responders['GET $path'] = (request) {
      transport.responders.remove('GET $path');
      return response.respond(request);
    };
    return response;
  }

  Future<Object?> inviterOnNextJoin({String? siteUrl}) async {
    await controller.join(
      siteUrl: siteUrl ?? _firstSite.url,
      siteName: 'Voice',
      room: VoiceRoom.fromJson(_room),
    );
    return transport.writes.last.body['invited_by'];
  }
}

final class _RouteHost implements PluginRouteNavigationHost {
  @override
  final sites = [_firstSite, _secondSite];
  String selectedUrl = _firstSite.url;
  void Function()? onSelect;
  final pushed = <({String? siteUrl, ContentRoute route})>[];

  // Match the production host's fresh value projections; site object
  // identity cannot be used as a navigation or account lifetime token.
  @override
  PluginRouteSite? get currentSite {
    final site = sites.where((site) => site.url == selectedUrl).firstOrNull;
    return site == null
        ? null
        : PluginRouteSite(
            url: site.url,
            title: site.title,
            isConnected: site.isConnected,
          );
  }

  @override
  ContentRoute? currentContent = const ContentRoute(
    id: 'latest',
    title: 'Latest',
    icon: DIcons.list,
  );

  @override
  void selectInstance(int index) {
    selectedUrl = sites[index].url;
    currentContent = ContentRoute(
      id: 'latest',
      title: '$selectedUrl latest',
      icon: DIcons.list,
    );
    onSelect?.call();
  }

  @override
  void pushContent(ContentRoute route) {
    pushed.add((siteUrl: currentSite?.url, route: route));
    currentContent = route;
  }

  @override
  void replaceCurrentContent(ContentRoute route) => currentContent = route;

  @override
  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    bool highlight = false,
  }) => throw UnimplementedError();
}
