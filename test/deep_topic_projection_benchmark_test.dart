import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/topic_reader_projections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

final class _CountingStore extends Store {
  int reads = 0;

  @override
  T? read<T extends Storable<T>>(String siteUrl, Object id) {
    if (T == Post) reads++;
    return super.read<T>(siteUrl, id);
  }
}

void main() {
  test('cold and structurally invalidated deep reader workload', () {
    const site = 'https://benchmark.example';
    final reports = <Map<String, Object>>[];
    for (final workload in [
      (20, 0, false),
      (20, 4000, false),
      (2000, 0, false),
      (16000, 0, false),
      (16000, 3800, false),
      (100000, 0, false),
      (16000, 4000, true),
    ]) {
      final (length, unrelated, head) = workload;
      final stream = List.generate(length, (i) => i * 3 + 100);
      final loaded = head
          ? 20
          : length < 200
          ? length
          : 200;
      final start = head ? 0 : length - loaded;
      final end = start + loaded;
      final target = head ? 10 : start + 1;
      final store = _CountingStore();
      final lifecycle = SiteLifecycle();
      final lease = lifecycle.capture(site);
      Post post(int index, {int? number}) => Post(
        id: stream[index],
        postNumber: number ?? index + 1,
        username: 'reader',
        cooked: 'body',
      );
      store.putAll(site, [for (var i = start; i < end; i++) post(i)]);
      store.putAll(site, [
        for (var i = 0; i < unrelated; i++)
          Post(
            id: 1000000 + i,
            postNumber: 1,
            username: 'other',
            cooked: 'body',
          ),
      ]);
      final samples = <Map<String, int>>[];
      for (var round = 0; round < 6; round++) {
        final owner = TopicReaderProjections(store);
        final reader = owner.forTab(site, 'tab', lease)!;
        store.reads = 0;
        final clock = Stopwatch()..start();
        final window = reader.project(stream, target);
        final initial = reader.initialIndex(
          window.ids,
          start + 2,
          hasEarlier: start > 0,
        );
        clock.stop();
        expect(window.range, (start, end - 1));
        expect(window.ids, stream.sublist(start, end));
        expect(initial, start > 0 ? 2 : 1);
        final cold = clock.elapsedMicroseconds;
        final coldReads = store.reads;
        final registrations =
            store.structureDependenciesForTesting.registrations;
        store.reads = 0;
        store.update<Post>(
          site,
          stream[start],
          (held) => post(start, number: start + 2),
        );
        clock.reset();
        clock.start();
        final changed = reader.project(stream, target);
        clock.stop();
        expect(changed.ids, window.ids);
        if (round > 0) {
          samples.add({
            'coldMicros': cold,
            'coldReads': coldReads,
            'dependencyIds': registrations,
            'invalidatedMicros': clock.elapsedMicroseconds,
            'invalidatedReads': store.reads,
          });
        }
        owner.dispose();
        store.put(site, post(start));
      }
      reports.add({
        'workload': 'cold-and-invalidated',
        'streamLength': length,
        'loaded': loaded,
        'unrelatedRecords': unrelated,
        'target': target,
        'samples': samples,
        'errors': 0,
      });
    }
    {
      const site = 'https://many-tabs.example';
      final store = _CountingStore();
      final lifecycle = SiteLifecycle();
      final owner = TopicReaderProjections(store);
      final stream = List.generate(16000, (i) => i + 1);
      store.putAll(site, [
        for (var id = 15801; id <= 16000; id++)
          Post(id: id, postNumber: id, username: 'reader', cooked: 'body'),
      ]);
      final tabs = [
        for (var i = 0; i < 8; i++)
          owner.forTab(site, '$i', lifecycle.capture(site))!,
      ];
      final windows = [for (final tab in tabs) tab.project(stream, 15900)];
      final samples = <Map<String, int>>[];
      for (var round = 0; round < 6; round++) {
        store.reads = 0;
        final clock = Stopwatch()..start();
        for (var i = 0; i < 250; i++) {
          final id = 20000 + i;
          store.put(
            site,
            Post(id: id, postNumber: 1, username: 'other', cooked: 'body'),
          );
          for (var tab = 0; tab < tabs.length; tab++) {
            if (!identical(tabs[tab].project(stream, 15900), windows[tab])) {
              fail('Unrelated arrival replaced window');
            }
          }
          store.remove<Post>(site, id);
          for (var tab = 0; tab < tabs.length; tab++) {
            if (!identical(tabs[tab].project(stream, 15900), windows[tab])) {
              fail('Unrelated removal replaced window');
            }
          }
        }
        clock.stop();
        expect(store.reads, 0);
        if (round > 0) {
          samples.add({
            'micros': clock.elapsedMicroseconds,
            'reads': store.reads,
          });
        }
      }
      reports.add({
        'workload': 'unrelated-mutations',
        'tabs': 8,
        'changesPerSample': 500,
        'samples': samples,
        'errors': 0,
      });
      owner.dispose();
    }
    final encoded = jsonEncode(reports);
    debugPrint('DEEP_TOPIC_PROJECTION $encoded', wrapWidth: 2048);
    final output = Platform.environment['DEEP_TOPIC_BENCHMARK_OUTPUT'];
    if (output != null) File(output).writeAsStringSync(encoded);
  });
}
