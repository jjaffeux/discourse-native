import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_feed.dart';
import 'package:discourse_native/src/shell/topic_feed_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

const _site = DiscourseInstance(
  url: 'https://benchmark.example',
  title: 'Benchmark',
);
const _destination = 'latest';
const _root = '/latest.json';
final _samples = _positiveOverride('FEED_BENCH_SAMPLES', 30);
const _warmups = 6;
final _operationsPerSample = _positiveOverride('FEED_BENCH_BATCH', 128);
const _output = String.fromEnvironment('TOPIC_FEED_BENCHMARK_OUTPUT');

enum _Workload {
  append300,
  appendShort20,
  appendDuplicates300,
  restore300,
  restoreReordered300,
  restoreProtected300,
  restoreMovedProtectedError300;

  bool get restores => index >= restore300.index;
  int get pageSize => this == appendShort20 ? 10 : 30;
  int get seedPages => restores ? 11 : (this == appendShort20 ? 2 : 10);
  bool get expectedError => this == restoreMovedProtectedError300;
  bool get movesIdentity =>
      this == restoreReordered300 || this == restoreMovedProtectedError300;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final report = <String, Object?>{
    'schema': 1,
    'release': kReleaseMode,
    'platform': Platform.operatingSystem,
    'runtime': Platform.version,
    'samples': _samples,
    'warmups': _warmups,
    'operationsPerSample': _operationsPerSample,
    'unit': 'microseconds_per_controller_endpoint',
    'timed':
        'awaited loadMore or ensureRange, including API future completion, '
        'store mutations, identity reconciliation, publication and listeners',
    'excluded':
        'fixture creation, seed loads, response construction, '
        'output verification, disposal, network and response decoding',
    'retention': 300,
    'cursorCheckpointLimit': '32 normally; 3 for dropped-checkpoint moves',
    'results': <Object?>[],
    'failures': <Object?>[],
  };
  try {
    _require(kReleaseMode, 'Build this driver in Flutter release mode.');
    for (final workload in _Workload.values) {
      final elapsedSamples = <double>[];
      var checksum = 0;
      var expectedErrors = 0;
      var notifications = 0;
      var requests = 0;
      for (var sample = -_warmups; sample < _samples; sample++) {
        final fixtures = <_Fixture>[];
        try {
          for (
            var operation = 0;
            operation < _operationsPerSample;
            operation++
          ) {
            fixtures.add(await _Fixture.seed(workload));
          }
          final timer = Stopwatch()..start();
          for (final fixture in fixtures) {
            await fixture.run();
          }
          timer.stop();
          for (final fixture in fixtures) {
            final checked = fixture.verify();
            if (sample >= 0) {
              checksum += checked;
              expectedErrors += fixture.feed.pageError ? 1 : 0;
              notifications += fixture.notifications;
              requests += fixture.api.requests;
            }
          }
          if (sample >= 0) {
            elapsedSamples.add(
              timer.elapsedTicks *
                  1000000 /
                  timer.frequency /
                  _operationsPerSample,
            );
          }
        } finally {
          for (final fixture in fixtures) {
            fixture.controller.dispose();
          }
        }
      }
      final sorted = elapsedSamples.toList()..sort();
      (report['results'] as List<Object?>).add({
        'workload': workload.name,
        'endpoint': workload.restores ? 'ensureRange' : 'loadMore',
        'seedRows': workload.seedPages * workload.pageSize,
        'retainedRowsBefore': workload.restores
            ? 300
            : workload.seedPages * workload.pageSize,
        'rawPageItems': workload.pageSize,
        'cursorCheckpointLimit': workload.movesIdentity ? 3 : 32,
        'samplesUsPerEndpoint': elapsedSamples,
        'medianUsPerEndpoint': sorted.length.isOdd
            ? sorted[sorted.length ~/ 2]
            : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2,
        'minUsPerEndpoint': sorted.first,
        'maxUsPerEndpoint': sorted.last,
        'measuredOperations': _samples * _operationsPerSample,
        'verifiedExpectedErrors': expectedErrors,
        'unexpectedErrors': 0,
        'timedApiRequests': requests,
        'timedNotifications': notifications,
        'checksum': checksum,
      });
    }
  } catch (error, stack) {
    (report['failures'] as List<Object?>).add({
      'error': error.toString(),
      'stack': stack.toString(),
    });
  }
  final encoded = jsonEncode(report);
  stdout.writeln(encoded);
  if (_output.isNotEmpty) await File(_output).writeAsString('$encoded\n');
  exit((report['failures'] as List<Object?>).isEmpty ? 0 : 1);
}

final class _Fixture {
  _Fixture(this.workload, this.api, this.controller, this.store) {
    controller.addListener(() {
      notifications++;
    });
  }

  final _Workload workload;
  final _Api api;
  final TopicFeedController controller;
  final Store store;
  int notifications = 0;

  TopicFeed get feed => controller.feedFor(_site.url, _destination)!;

  static Future<_Fixture> seed(_Workload workload) async {
    final api = _Api();
    final store = Store();
    final readers = <int>{};
    final controller = TopicFeedController(
      api: api,
      credentials: const _Credentials(),
      lifecycle: SiteLifecycle(),
      store: store,
      maximumCursorCheckpoints: workload.movesIdentity ? 3 : 32,
      readerTopics: (_, _) => readers,
    );
    final fixture = _Fixture(workload, api, controller, store);
    try {
      for (var page = 0; page < workload.seedPages; page++) {
        api.pages[_path(page)] = _page(
          List.generate(
            workload.pageSize,
            (i) => page * workload.pageSize + i + 1,
          ),
          next: _path(page + 1),
        );
      }
      await controller.load(
        instance: _site,
        destinationId: _destination,
        path: _root,
        incoming: null,
      );
      for (var page = 1; page < workload.seedPages; page++) {
        await controller.loadMore(instance: _site, destinationId: _destination);
      }
      _require(fixture.feed.error == null, 'Seed failed for ${workload.name}.');
      _require(
        fixture.feed.rowCount == workload.seedPages * workload.pageSize,
        'Wrong seed row count for ${workload.name}.',
      );
      _require(
        fixture.feed.topicIds.length ==
            (workload.restores ? 300 : workload.seedPages * workload.pageSize),
        'Wrong seed retention for ${workload.name}.',
      );
      if (workload.restores) {
        _require(
          fixture.feed.topicIdAt(0) == null,
          'Restore must miss row zero.',
        );
        api.pages[_root] = _page([
          if (workload.movesIdentity) 31 else 1,
          for (var id = 2; id <= 30; id++) id,
        ], next: _path(1));
        if (workload == _Workload.restoreProtected300) {
          readers.add(301);
          final owner = Object();
          controller.retainFeed(_site.url, _destination, owner: owner);
          controller.updateViewport(
            _site.url,
            _destination,
            owner: owner,
            firstRow: 300,
            lastRow: 309,
          );
        } else if (workload.expectedError) {
          readers.add(31);
        }
      } else {
        final start = workload.seedPages * workload.pageSize;
        api.pages[_path(workload.seedPages)] = _page(
          workload == _Workload.appendDuplicates300
              ? [
                  for (var id = 291; id <= 310; id++) id,
                  for (var id = 301; id <= 310; id++) id,
                ]
              : List.generate(workload.pageSize, (i) => start + i + 1),
          next: _path(workload.seedPages + 1),
        );
      }
      fixture.notifications = 0;
      api.requests = 0;
      return fixture;
    } catch (_) {
      controller.dispose();
      rethrow;
    }
  }

  Future<void> run() => workload.restores
      ? controller.ensureRange(
          instance: _site,
          destinationId: _destination,
          firstRow: 0,
          lastRow: 29,
        )
      : controller.loadMore(instance: _site, destinationId: _destination);

  int verify() {
    final result = feed;
    _require(
      api.requests == 1,
      'Expected one timed API request for ${workload.name}.',
    );
    _require(
      notifications >= 1,
      'No endpoint notifications for ${workload.name}.',
    );
    _require(
      result.loaded && !result.loading && !result.loadingMore,
      'Endpoint did not settle.',
    );
    _require(
      result.pageError == workload.expectedError,
      'Unexpected page error for ${workload.name}.',
    );
    _require(
      (result.error != null) == workload.expectedError,
      'Unexpected error for ${workload.name}.',
    );
    final expected = <int, int>{};
    late final int total;
    late final String cursor;
    if (workload.restores) {
      total = 330;
      cursor = _path(11);
      if (workload.expectedError) {
        for (var row = 30; row < 330; row++) {
          expected[row] = row + 1;
        }
      } else {
        for (var row = 0; row < 30; row++) {
          expected[row] = row == 0 && workload.movesIdentity ? 31 : row + 1;
        }
        for (var row = 60; row < 330; row++) {
          expected[row] = row + 1;
        }
      }
    } else {
      total = workload == _Workload.appendDuplicates300
          ? 310
          : (workload.seedPages + 1) * workload.pageSize;
      cursor = _path(workload.seedPages + 1);
      final first = total > 300 ? total - 300 : 0;
      for (var row = first; row < total; row++) {
        expected[row] = row + 1;
      }
    }
    _require(
      result.rowCount == total,
      'Wrong endpoint row count for ${workload.name}.',
    );
    _require(
      result.nextPagePath == cursor,
      'Cursor changed for ${workload.name}.',
    );
    _require(
      result.topicIds.length == expected.length,
      'Wrong retained count for ${workload.name}.',
    );
    _require(
      result.topicIds.toSet().length == expected.length,
      'Duplicate retained identities.',
    );
    var checksum = total;
    for (var row = 0; row < total; row++) {
      final id = result.topicIdAt(row);
      _require(
        id == expected[row],
        'Wrong ID at row $row for ${workload.name}: $id != ${expected[row]}.',
      );
      if (id != null) {
        _require(
          store.read<Topic>(_site.url, id)?.id == id,
          'Published ID lacks a stored topic.',
        );
        checksum += (row + 1) * id;
      }
    }
    return checksum;
  }
}

String _path(int page) => page == 0 ? _root : '/latest.json?page=$page';

TopicList _page(List<int> ids, {required String next}) => TopicList(
  topics: [
    for (final id in ids) Topic(id: id, title: 'Topic $id', slug: 'topic-$id'),
  ],
  moreTopicsUrl: next,
);

final class _Credentials implements SiteApiKeyReader {
  const _Credentials();

  @override
  Future<String?> apiKeyFor(String siteUrl) => Future.value(null);
}

final class _Api implements TopicFeedsApi {
  final Map<String, TopicList> pages = {};
  int requests = 0;

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) {
    requests++;
    return Future.value(
      pages[path] ?? (throw StateError('Unexpected page $path.')),
    );
  }

  @override
  Future<Topic> topicSummary({
    required String siteUrl,
    required int id,
    String? apiKey,
    String? clientId,
  }) => throw StateError('Unexpected summary request $id.');

  @override
  Future<List<int>> dismissNewTopics({
    required String siteUrl,
    required String apiKey,
    required bool dismissTopics,
    required bool dismissPosts,
    int? categoryId,
    String? tagName,
    List<int>? topicIds,
    String? clientId,
  }) => throw StateError('Unexpected dismiss request.');
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

int _positiveOverride(String name, int fallback) {
  final value = Platform.environment[name];
  if (value == null) return fallback;
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    throw ArgumentError('$name must be a positive integer.');
  }
  return parsed;
}
