import 'dart:async';

import 'package:discourse_plugin_api/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const siteUrl = 'https://forum.example.com';

  test(
    'records immutable read and write snapshots through live views',
    () async {
      final transport = RecordingPluginTransport(
        responses: {
          'GET /plugin/items.json': {'items': <Object?>[]},
          'POST /plugin/items.json': {'ok': true},
        },
      );
      final nested = <Object?>['held'];
      final body = <String, Object?>{'nested': nested};

      await transport.pluginGetJson(
        siteUrl: siteUrl,
        path: '/plugin/items.json',
        apiKey: null,
      );
      await transport.pluginWriteJson(
        siteUrl: siteUrl,
        path: '/plugin/items.json',
        method: 'post',
        apiKey: 'secret',
        body: body,
        clientId: 'client',
      );
      nested.add('late');
      body['late'] = true;

      expect(transport.requests, hasLength(2));
      expect(transport.reads.single.expectsList, isFalse);
      expect(transport.writes.single.method, 'POST');
      expect(transport.writes.single.clientId, 'client');
      expect(transport.writes.single.body, {
        'nested': ['held'],
      });
      expect(() => transport.requests.clear(), throwsUnsupportedError);
      expect(
        () => transport.writes.single.body['extra'] = true,
        throwsUnsupportedError,
      );
      expect(
        () => (transport.writes.single.body['nested']! as List<Object?>).add(
          'extra',
        ),
        throwsUnsupportedError,
      );
    },
  );

  test('supports mutable object and list route tables', () async {
    final transport = RecordingPluginTransport();
    transport.responses['GET /plugin/object.json'] = {'value': 1};
    transport.listResponses['GET /plugin/list.json'] = [
      {'value': 2},
    ];

    expect(
      await transport.pluginGetJson(
        siteUrl: siteUrl,
        path: '/plugin/object.json',
        apiKey: null,
      ),
      {'value': 1},
    );
    expect(
      await transport.pluginGetJsonList(
        siteUrl: siteUrl,
        path: '/plugin/list.json',
        apiKey: null,
      ),
      [
        {'value': 2},
      ],
    );
    expect(transport.reads.map((request) => request.expectsList), [
      false,
      true,
    ]);
  });

  test(
    'awaits route responders and consumes configured failures once',
    () async {
      final response = Completer<Object?>();
      final transport = RecordingPluginTransport(
        responses: {
          'POST /plugin/retry.json': {'ok': true},
        },
        failures: {
          'POST /plugin/retry.json': StateError('first attempt failed'),
        },
        responders: {'GET /plugin/held.json': (_) => response.future},
      );

      await expectLater(
        transport.pluginWriteJson(
          siteUrl: siteUrl,
          path: '/plugin/retry.json',
          method: 'POST',
          apiKey: 'secret',
          body: const {},
        ),
        throwsStateError,
      );
      expect(
        await transport.pluginWriteJson(
          siteUrl: siteUrl,
          path: '/plugin/retry.json',
          method: 'POST',
          apiKey: 'secret',
          body: const {},
        ),
        {'ok': true},
      );

      final held = transport.pluginGetJson(
        siteUrl: siteUrl,
        path: '/plugin/held.json',
        apiKey: null,
      );
      response.complete({'held': false});
      expect(await held, {'held': false});
    },
  );

  test('fails loudly for unmatched and wrong-shaped routes', () async {
    final transport = RecordingPluginTransport(
      responses: {
        'GET /plugin/object.json': {'value': 1},
      },
      listResponses: {
        'GET /plugin/list.json': [
          {'value': 2},
        ],
      },
      responders: {'GET /plugin/bad-responder.json': (_) async => <Object?>[]},
    );

    await expectLater(
      transport.pluginGetJson(
        siteUrl: siteUrl,
        path: '/plugin/missing.json',
        apiKey: null,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('No object response configured'),
        ),
      ),
    );
    await expectLater(
      transport.pluginGetJsonList(
        siteUrl: siteUrl,
        path: '/plugin/object.json',
        apiKey: null,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('has an object response'),
        ),
      ),
    );
    await expectLater(
      transport.pluginGetJson(
        siteUrl: siteUrl,
        path: '/plugin/list.json',
        apiKey: null,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('has a list response'),
        ),
      ),
    );
    await expectLater(
      transport.pluginGetJson(
        siteUrl: siteUrl,
        path: '/plugin/bad-responder.json',
        apiKey: null,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('expected a JSON object'),
        ),
      ),
    );
  });
}
