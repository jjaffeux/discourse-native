import 'dart:async';

import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/data/topic_presentation_store.dart';
import 'package:discourse_native/src/models/topic_presentation.dart';
import 'package:discourse_native/src/shell/topic_presentation_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final mode in TopicPresentation.values) {
    test('explicit $mode preference survives a new controller', () async {
      final controller = TopicPresentationController();
      addTearDown(controller.dispose);
      controller.select(TopicPresentation.merged);
      controller.select(mode);
      final restored = TopicPresentationController();
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.preference, mode);
    });
  }

  test('legacy sheet and dock modes migrate to merged and split', () async {
    for (final (stored, expected) in [
      ('sheet', TopicPresentation.merged),
      ('docked', TopicPresentation.split),
    ]) {
      SharedPreferences.setMockInitialValues({
        TopicPresentationStore.storageKey: stored,
      });
      expect(await const TopicPresentationStore().read(), expected);
    }
  });

  test('invalid stored mode uses the split default', () async {
    SharedPreferences.setMockInitialValues({
      TopicPresentationStore.storageKey: 'unknown',
    });
    expect(
      await const TopicPresentationStore().read(),
      TopicPresentation.split,
    );
  });

  test(
    'delayed preference load cannot overwrite a newer explicit choice',
    () async {
      final persistence = _DelayedPersistence();
      final store = TopicPresentationStore(persistence: persistence);
      final controller = TopicPresentationController(store: store);
      addTearDown(controller.dispose);
      final loading = controller.load();
      controller.select(TopicPresentation.split);
      persistence.result.complete('sheet');
      await loading;
      expect(controller.preference, TopicPresentation.split);
      expect(await store.read(), TopicPresentation.split);
    },
  );
}

class _DelayedPersistence implements ScalarPreferencePersistence<String> {
  final result = Completer<String?>();
  String? saved;

  @override
  Future<String?> read(String key) async => saved ?? await result.future;

  @override
  Future<bool> write(String key, String value) async {
    saved = value;
    return true;
  }
}
