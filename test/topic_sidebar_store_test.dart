import 'dart:async';

import 'package:discourse_native/src/data/site_preference_keys.dart';
import 'package:discourse_native/src/data/topic_sidebar_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TopicSidebarStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = TopicSidebarStore();
  });

  test('the sidebar is visible until a hidden choice is saved', () async {
    expect(await store.read(siteUrl: 'https://meta.discourse.org'), isFalse);

    await store.write(siteUrl: 'https://meta.discourse.org', collapsed: true);

    expect(await store.read(siteUrl: 'https://meta.discourse.org'), isTrue);
  });

  test('visibility choices are independent by forum', () async {
    await store.write(siteUrl: 'https://meta.discourse.org', collapsed: true);

    expect(await store.read(siteUrl: 'https://team.discourse.org'), isFalse);
    expect(await store.read(siteUrl: 'https://meta.discourse.org'), isTrue);
  });

  test('a replacement store reads after an accepted write', () async {
    final persistence = _GatedSidebarPersistence();
    final first = TopicSidebarStore(persistence: persistence);
    final replacement = TopicSidebarStore(persistence: persistence);

    final write = first.write(
      siteUrl: 'https://meta.discourse.org',
      collapsed: true,
    );
    await persistence.writeStarted.future;
    final read = replacement.read(siteUrl: 'https://meta.discourse.org');
    await Future<void>.delayed(Duration.zero);
    expect(persistence.reads, 0);

    persistence.finishWrite.complete();
    await write;
    expect(await read, isTrue);
    expect(persistence.reads, 1);
  });

  test('a saved choice is available while its disk write is pending', () async {
    final persistence = _GatedSidebarPersistence();
    final store = TopicSidebarStore(persistence: persistence);
    await store.ensure(siteUrl: 'https://meta.discourse.org');
    final write = store.write(
      siteUrl: 'https://meta.discourse.org',
      collapsed: true,
    );
    await persistence.writeStarted.future;
    expect(store.collapsedFor('https://meta.discourse.org'), isTrue);
    expect(await store.ensure(siteUrl: 'https://meta.discourse.org'), isTrue);
    expect(persistence.reads, 1);
    persistence.finishWrite.complete();
    await write;
  });

  test('a forgotten forum keeps nothing a read in flight answers', () async {
    const meta = 'https://meta.discourse.org';
    const team = 'https://team.discourse.org';
    final persistence = _HeldReadPersistence()..values[meta] = true;
    final store = TopicSidebarStore(persistence: persistence);
    await store.write(siteUrl: team, collapsed: true);
    persistence.holdReads = true;
    final reading = store.ensure(siteUrl: meta);

    store.forgetSites(ForgottenSites.removed(meta, keeping: const [team]));
    persistence.releaseReads.complete();

    expect(await reading, isTrue);
    expect(store.collapsedFor(meta), isNull);
    expect(store.collapsedFor(team), isTrue);
  });
}

final class _HeldReadPersistence implements TopicSidebarPersistence {
  final values = <String, bool>{};
  final releaseReads = Completer<void>();
  bool holdReads = false;

  @override
  Future<bool?> readCollapsed({required String siteUrl}) async {
    if (holdReads && !releaseReads.isCompleted) await releaseReads.future;
    return values[siteUrl];
  }

  @override
  Future<bool> writeCollapsed({
    required String siteUrl,
    required bool collapsed,
  }) async {
    values[siteUrl] = collapsed;
    return true;
  }
}

final class _GatedSidebarPersistence implements TopicSidebarPersistence {
  final writeStarted = Completer<void>();
  final finishWrite = Completer<void>();
  bool? value;
  int reads = 0;

  @override
  Future<bool?> readCollapsed({required String siteUrl}) async {
    reads += 1;
    return value;
  }

  @override
  Future<bool> writeCollapsed({
    required String siteUrl,
    required bool collapsed,
  }) async {
    writeStarted.complete();
    await finishWrite.future;
    value = collapsed;
    return true;
  }
}
