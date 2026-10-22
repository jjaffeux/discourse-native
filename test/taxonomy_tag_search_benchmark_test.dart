import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service_io.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _queries = [
  (term: '', categoryId: null),
  (term: 't', categoryId: null),
  (term: 'TaG-0', categoryId: null),
  (term: 'group-07', categoryId: null),
  (term: 'tag-04999', categoryId: null),
  (term: 'absent', categoryId: null),
  (term: '', categoryId: 42),
  (term: 'TaG', categoryId: 42),
];

typedef _Query = ({String term, int? categoryId});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('production taxonomy tag search preparation benchmark', () async {
    final report = <String, Object?>{
      'runtime': 'Flutter test VM, debug JIT, immediate fake API, no network',
      'failures': 0,
      'cases': <Object?>[],
    };
    for (final size in [30, 5000]) {
      final api = _BenchmarkApi(_tags(size, 0));
      final shell = ShellController(
        instanceStore: FakeInstanceStore([
          instance(
            'meta.discourse.org',
          ).copyWith(user: const DiscourseUser(id: 7, username: 'reader')),
        ]),
        api: api,
        authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        ownsApi: false,
      );
      try {
        await shell.load();
        await pumpEventQueue();
        final remoteSets = [for (var i = 0; i < 3; i++) _remote(i)];
        final expected = <(int, int, int), List<TopicFilterLookupValue>>{};
        for (var generation = 0; generation < 9; generation++) {
          for (var response = 0; response < remoteSets.length; response++) {
            for (var q = 0; q < _queries.length; q++) {
              expected[(generation, response, q)] = _reference(
                _tags(size, generation),
                remoteSets[response],
                _queries[q],
              );
            }
          }
        }
        final selectiveQuery = (
          term: 'tag-${(size - 1).toString().padLeft(5, '0')}',
          categoryId: null,
        );
        final selectiveSources = [
          for (var generation = 9; generation < 14; generation++)
            _tags(size, generation),
        ];
        final selectiveExpected = [
          for (final tags in selectiveSources)
            _reference(tags, const [], selectiveQuery),
        ];
        for (final expected in selectiveExpected) {
          expect(expected, hasLength(1));
        }
        var checksum = 0;
        var searchCalls = 0;
        Future<int> searches(int generation, int repeats) async {
          var micros = 0;
          for (var iteration = 0; iteration < repeats; iteration++) {
            final response = iteration % remoteSets.length;
            api.response = remoteSets[response];
            for (var q = 0; q < _queries.length; q++) {
              final query = _queries[q];
              final watch = Stopwatch()..start();
              final actual = await shell.searchFilterTags(
                siteUrl: _site,
                term: query.term,
                categoryId: query.categoryId,
              );
              watch.stop();
              micros += watch.elapsedMicroseconds;
              expect(actual, expected[(generation, response, q)]);
              for (final tag in actual) {
                for (final code
                    in '${tag.name}|${tag.description};'.codeUnits) {
                  checksum = ((checksum * 31) + code) & 0x7fffffff;
                }
              }
              searchCalls++;
            }
          }
          return micros;
        }

        final coldWatch = Stopwatch()..start();
        await shell.loadTags(_site);
        coldWatch.stop();
        final coldSearchUs = await searches(0, 1);
        await searches(0, 5);
        final warmUs = await searches(0, 40);
        final profileOutput =
            Platform.environment['TAXONOMY_TAG_SEARCH_PROFILE'];
        if (size == 5000 && profileOutput != null) {
          final info = await developer.Service.getInfo();
          final uri = info.serverUri!;
          final socket = uri.replace(scheme: 'ws', path: '${uri.path}ws');
          final service = await vmServiceConnectUri(socket.toString());
          final isolateId = developer.Service.getIsolateId(Isolate.current)!;
          await service.clearCpuSamples(isolateId);
          final start = developer.Timeline.now;
          var consumed = 0;
          for (var i = 0; i < 300; i++) {
            final values = await shell.searchFilterTags(
              siteUrl: _site,
              term: i.isEven ? '' : 'tag',
            );
            consumed += values.length + values.first.name.length;
          }
          final duration = developer.Timeline.now - start;
          final samples = await service.getCpuSamples(
            isolateId,
            start,
            duration,
          );
          expect(samples.sampleCount, greaterThan(0));
          File(profileOutput).writeAsStringSync(jsonEncode(samples.toJson()));
          expect(consumed, greaterThan(1000000));
          await service.dispose();
        }
        var refreshLoadUs = 0;
        var refreshSearchUs = 0;
        for (var generation = 1; generation <= 8; generation++) {
          api.currentTags = _tags(size, generation);
          final watch = Stopwatch()..start();
          await shell.loadTags(_site, force: true);
          watch.stop();
          refreshLoadUs += watch.elapsedMicroseconds;
          refreshSearchUs += await searches(generation, 1);
        }
        final selectiveRefreshTimes = <int>[];
        api.response = const [];
        for (
          var generation = 0;
          generation < selectiveSources.length;
          generation++
        ) {
          api.currentTags = selectiveSources[generation];
          final watch = Stopwatch()..start();
          await shell.loadTags(_site, force: true);
          final actual = await shell.searchFilterTags(
            siteUrl: _site,
            term: selectiveQuery.term,
          );
          watch.stop();
          selectiveRefreshTimes.add(watch.elapsedMicroseconds);
          expect(actual, selectiveExpected[generation]);
          for (final tag in actual) {
            for (final code in '${tag.name}|${tag.description};'.codeUnits) {
              checksum = ((checksum * 31) + code) & 0x7fffffff;
            }
          }
          searchCalls++;
        }
        expect(
          api.searchCalls,
          searchCalls + (size == 5000 && profileOutput != null ? 300 : 0),
        );
        expect(api.tagLoads, 14);
        expect(checksum, isNonZero);
        (report['cases']! as List<Object?>).add({
          'known_tags': size,
          'cold_load_us': coldWatch.elapsedMicroseconds,
          'cold_search_us': coldSearchUs,
          'cold_total_us': coldWatch.elapsedMicroseconds + coldSearchUs,
          'warm_search_us': warmUs,
          'warm_search_calls': 40 * _queries.length,
          'refresh_load_us': refreshLoadUs,
          'refresh_search_us': refreshSearchUs,
          'refresh_total_us': refreshLoadUs + refreshSearchUs,
          'refresh_generations': 8,
          'selective_refresh_total_us': selectiveRefreshTimes.fold<int>(
            0,
            (sum, value) => sum + value,
          ),
          'selective_refresh_us_samples': selectiveRefreshTimes,
          'selective_refresh_generations': selectiveSources.length,
          'selective_matches_per_search': 1,
          'tag_loads': api.tagLoads,
          'search_calls_including_warmup': searchCalls,
          'remote_results_per_regular_call': remoteSets.first.length,
          'remote_results_per_selective_call': 0,
          'checksum': checksum,
        });
      } finally {
        shell.dispose();
        await pumpEventQueue();
      }
    }
    final output = Platform.environment['TAXONOMY_TAG_SEARCH_OUTPUT']!;
    File(output).writeAsStringSync(jsonEncode(report));
    stdout.writeln('TAXONOMY_TAG_SEARCH ${jsonEncode(report)}');
  }, skip: Platform.environment['TAXONOMY_TAG_SEARCH_OUTPUT'] == null);
}

List<SidebarTag> _tags(int size, int generation) => [
  for (var i = 0; i < size; i++)
    SidebarTag(
      id: i + 1,
      name:
          '${i.isEven ? 'TaG' : 'tag'}-${i.toString().padLeft(5, '0')}'
          '-group-${(i % 17).toString().padLeft(2, '0')}'
          '${generation.isOdd && i % 19 == 0 ? '-changed' : ''}',
      slug: 'tag-$i',
      count: (i * 43 + generation * 97) % 503,
      pmOnly: i % 101 == 0,
    ),
];

List<TopicFilterLookupValue> _remote(int generation) => [
  for (var i = 0; i < 100; i++)
    TopicFilterLookupValue(
      name: i < 75
          ? 'TAG-${i.toString().padLeft(5, '0')}'
                '-group-${(i % 17).toString().padLeft(2, '0')}'
          : 'remote-${i % 23}',
      description: switch (i % 7) {
        0 => null,
        1 => 'a description',
        2 => ' 41 ',
        3 => '-7',
        4 => '0x1f',
        _ => '${(i * 71 + generation * 31) % 509}',
      },
    ),
];

List<TopicFilterLookupValue> _reference(
  List<SidebarTag> local,
  List<TopicFilterLookupValue> remote,
  _Query query,
) {
  final rows = <({String key, int rank, TopicFilterLookupValue value})>[];
  final keys = <String>{};
  for (final tag in remote.reversed) {
    final key = tag.name.toLowerCase();
    if (!keys.add(key)) continue;
    rows.add((
      key: key,
      rank: int.tryParse(tag.description ?? '') ?? 0,
      value: tag,
    ));
  }
  if (query.categoryId == null) {
    final term = query.term.toLowerCase();
    for (final tag in local) {
      final key = tag.name.toLowerCase();
      if (tag.pmOnly || !key.contains(term) || !keys.add(key)) continue;
      rows.add((
        key: key,
        rank: tag.count,
        value: TopicFilterLookupValue(
          name: tag.name,
          description: '${tag.count}',
        ),
      ));
    }
  }
  rows.sort((a, b) {
    if (a.rank != b.rank) return a.rank > b.rank ? -1 : 1;
    return a.key.compareTo(b.key);
  });
  return [for (final row in rows) row.value];
}

final class _BenchmarkApi extends FakeDiscourseApi {
  _BenchmarkApi(this.currentTags)
    : super(
        feeds: const {'/latest.json': []},
        siteConfigs: const {_site: SiteConfig(maxTagSearchResults: 100)},
      );

  List<SidebarTag> currentTags;
  List<TopicFilterLookupValue> response = const [];
  int searchCalls = 0;
  int tagLoads = 0;

  @override
  Future<List<SidebarTag>> tags({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) async {
    tagLoads++;
    return currentTags;
  }

  @override
  Future<List<TopicFilterLookupValue>> searchFilterTags({
    required String siteUrl,
    required String term,
    int? categoryId,
    int limit = 5,
    String? apiKey,
    String? clientId,
  }) async {
    searchCalls++;
    return response;
  }
}
