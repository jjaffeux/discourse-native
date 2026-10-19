import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/plugins/chat/chat_global_search.dart';
import 'package:discourse_native/src/shell/global_search_api.dart';
import 'package:discourse_native/src/shell/global_search_controller.dart';
import 'package:discourse_native/src/shell/global_search_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const _site = 'https://search-benchmark.invalid';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'mixed latency global search consumes first and final results',
    () async {
      for (final scenario in [
        'slow-chat',
        'slow-forum',
        'failed-chat',
        'query-replacement',
        'account-retirement',
      ]) {
        final stopwatch = Stopwatch();
        final dispatches = <String, int>{};
        final completions = <String, int>{};
        final api = DiscourseApi(
          client: MockClient((request) async {
            final uri = request.url;
            if (uri.path == '/site/settings.json') {
              return http.Response(
                '{"chat_enabled":true,"chat_search_enabled":true}',
                200,
              );
            }
            if (uri.path == '/session/current.json') {
              return http.Response(
                '{"current_user":{"has_chat_enabled":true,"can_chat":true}}',
                200,
              );
            }
            if (uri.path == '/directory-columns.json') {
              return http.Response('{}', 200);
            }
            final source = uri.path.startsWith('/chat/')
                ? 'chat'
                : uri.queryParameters.containsKey('search_context[id]')
                ? 'context'
                : uri.queryParameters['type_filter'] == 'private_messages'
                ? 'messages'
                : 'forum';
            final query =
                uri.queryParameters['term'] ??
                uri.queryParameters['query'] ??
                '';
            final sourceKey =
                scenario.endsWith('replacement') ||
                    scenario.endsWith('retirement')
                ? '$query:$source'
                : source;
            dispatches[sourceKey] = stopwatch.elapsedMicroseconds;
            final delay = switch (source) {
              'chat' => scenario == 'slow-forum' ? 40 : 400,
              'forum' => scenario == 'slow-forum' ? 400 : 40,
              'context' => 120,
              _ => 220,
            };
            await Future<void>.delayed(Duration(milliseconds: delay));
            completions[sourceKey] = stopwatch.elapsedMicroseconds;
            if (source == 'chat') {
              return http.Response(
                jsonEncode({
                  'messages': [
                    {
                      'id': 7,
                      'chat_channel_id': 2,
                      'channel': {'id': 2, 'slug': 'design', 'title': 'Design'},
                      'user': {'username': 'mira'},
                      'message': query,
                    },
                  ],
                }),
                scenario == 'failed-chat' ? 503 : 200,
              );
            }
            final id = source == 'messages' ? 43 : 42;
            return http.Response(
              jsonEncode({
                'posts': [
                  {'id': id, 'topic_id': id, 'post_number': 1, 'blurb': query},
                ],
                'topics': [
                  {
                    'id': id,
                    'title': '$source result',
                    'slug': 'result',
                    if (source == 'messages') 'archetype': 'private_message',
                  },
                ],
              }),
              200,
            );
          }),
        );
        final lifecycle = SiteLifecycle();
        final controller =
            GlobalSearchController(
              api: GlobalSearchApi(transport: api),
              credentials: FakeApiCredentialReader()..keys[_site] = 'key',
              lifecycle: lifecycle,
            )..configure(
              siteUrl: _site,
              capabilities: const GlobalSearchCapabilities(
                authenticated: true,
                contributions: [ChatGlobalSearch()],
                enabledContributions: {'chat'},
              ),
            );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        controller.setPageContext(topicId: 42, topicTitle: 'Context');
        int? firstUs;
        final done = Completer<void>();
        final snapshots = <List<String>>[];
        final staleResults = <String>[];
        controller.addListener(() {
          if (controller.query != 'benchmark') return;
          staleResults.addAll(
            controller.results
                .where((r) => r.excerpt == 'benchmark-old')
                .map((r) => r.id),
          );
          final ids = controller.results.map((r) => r.id).toList();
          if (ids.isNotEmpty) {
            firstUs ??= stopwatch.elapsedMicroseconds;
            snapshots.add(ids);
          }
          if (controller.phase != GlobalSearchPhase.loading &&
              !done.isCompleted) {
            done.complete();
          }
        });
        stopwatch.start();
        final interrupted =
            scenario == 'query-replacement' || scenario == 'account-retirement';
        controller.setQuery(interrupted ? 'benchmark-old' : 'benchmark');
        if (interrupted) {
          Timer(const Duration(milliseconds: 450), () {
            if (scenario == 'account-retirement') {
              lifecycle.invalidate(_site);
              controller.configure(
                siteUrl: _site,
                capabilities: controller.capabilities,
              );
              controller.setPageContext(topicId: 42, topicTitle: 'Context');
            }
            controller.setQuery('benchmark');
          });
        }
        await done.future.timeout(const Duration(seconds: 5));
        stopwatch.stop();
        expect(firstUs, isNotNull);
        expect(staleResults, isEmpty);
        final sourceCount = interrupted ? 8 : 4;
        expect(dispatches.length, sourceCount);
        expect(completions.length, sourceCount);
        expect(
          controller.results.map((r) => r.title),
          containsAll(['forum result', 'messages result']),
        );
        expect(
          controller.results.any((r) => r.id.startsWith('in-topic:')),
          isTrue,
        );
        expect(
          controller.results.any((r) => r.id == 'chat:7'),
          scenario != 'failed-chat',
        );
        expect(
          controller.sections.where((s) => s.error != null).length,
          scenario == 'failed-chat' ? 1 : 0,
        );
        final data = {
          'scenario': scenario,
          'variant': Platform.environment['SEARCH_BENCH_VARIANT'] ?? 'current',
          'revision':
              Platform.environment['SEARCH_BENCH_REVISION'] ?? 'working',
          'firstUs': firstUs,
          'finalUs': stopwatch.elapsedMicroseconds,
          'dispatchesUs': dispatches,
          'completionsUs': completions,
          'snapshots': snapshots,
          'staleResults': staleResults,
          'resultIds': controller.results.map((r) => r.id).toList(),
          'resultPaths': controller.results.map((r) => r.path).toList(),
          'errors': controller.sections.where((s) => s.error != null).length,
        };
        final output = Platform.environment['SEARCH_BENCH_OUTPUT'];
        if (output != null) {
          File(
            output,
          ).writeAsStringSync('${jsonEncode(data)}\n', mode: FileMode.append);
        }
        debugPrint('SEARCH_BENCH ${jsonEncode(data)}');
        controller.dispose();
        api.close();
      }
    },
  );
}
