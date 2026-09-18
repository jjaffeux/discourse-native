import 'package:shared_preferences/shared_preferences.dart';

import '../models/topic_presentation.dart';
import 'scalar_preference_repository.dart';

class TopicPresentationStore {
  const TopicPresentationStore({
    this.persistence = const _TopicPresentationPersistence(),
  });

  static const storageKey = 'discourse_native.topic_presentation';
  final ScalarPreferencePersistence<String> persistence;

  ScalarPreferenceRepository<String> get _repository =>
      ScalarPreferenceRepository(
        persistence: persistence,
        key: storageKey,
        readOperation: 'topicPresentation.read',
        writeOperation: 'topicPresentation.write',
        writeFailureMessage: 'Could not save topic view.',
      );

  Future<TopicPresentation> read() async {
    final stored = await _repository.read();
    final value = stored == 'sheet'
        ? 'merged'
        : stored == 'docked'
        ? 'split'
        : stored;
    return TopicPresentation.values
            .where((mode) => mode.name == value)
            .firstOrNull ??
        TopicPresentation.split;
  }

  Future<void> write(TopicPresentation mode) => _repository.write(mode.name);
}

final class _TopicPresentationPersistence
    extends SharedPreferencesScalarPreferencePersistence<String> {
  const _TopicPresentationPersistence();

  @override
  String? readValue(SharedPreferences preferences, String key) =>
      preferences.getString(key);

  @override
  Future<bool> writeValue(
    SharedPreferences preferences,
    String key,
    String value,
  ) => preferences.setString(key, value);
}
