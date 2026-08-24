import 'dart:async';

import 'package:discourse_native/src/data/topic_recommendations_panel_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = TopicRecommendationsPanelStore();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('the panel is expanded until a collapsed choice is saved', () async {
    expect(await store.read(siteUrl: 'https://meta.discourse.org'), isFalse);

    await store.write(siteUrl: 'https://meta.discourse.org', collapsed: true);

    expect(await store.read(siteUrl: 'https://meta.discourse.org'), isTrue);
  });

  test('collapse choices are independent by forum', () async {
    await store.write(siteUrl: 'https://meta.discourse.org', collapsed: true);

    expect(await store.read(siteUrl: 'https://team.discourse.org'), isFalse);
    expect(await store.read(siteUrl: 'https://meta.discourse.org'), isTrue);
  });

  test('a replacement store reads after an accepted write', () async {
    final persistence = _GatedPanelPersistence();
    final first = TopicRecommendationsPanelStore(persistence: persistence);
    final replacement = TopicRecommendationsPanelStore(
      persistence: persistence,
    );

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
}

final class _GatedPanelPersistence
    implements TopicRecommendationsPanelPersistence {
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
