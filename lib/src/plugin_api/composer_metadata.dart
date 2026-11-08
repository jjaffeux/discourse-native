import 'package:flutter/foundation.dart';

import '../models/plugin_data.dart';
import '../models/preserved_json.dart';

@immutable
final class PluginComposerContext {
  const PluginComposerContext({
    required this.siteUrl,
    required this.createsTopic,
    required this.isEdit,
    required this.isPrivateMessage,
    this.categoryId,
    this.categoryData = PluginData.none,
    this.topicData = PluginData.none,
    this.siteSettings = PluginData.none,
    this.currentUserData = PluginData.none,
  });

  final String siteUrl;
  final bool createsTopic;
  final bool isEdit;
  final bool isPrivateMessage;
  final int? categoryId;
  final PluginData categoryData;
  final PluginData topicData;
  final PluginData siteSettings;
  final PluginData currentUserData;
}

@immutable
final class PluginComposerLabels {
  const PluginComposerLabels({this.title, this.submit});
  final String? title;
  final String? submit;
}

abstract interface class ComposerMetadataEditorHost {
  PluginComposerContext get metadataContext;
  T? metadata<T extends Object>(PluginDataKey<T> key);
  bool updateMetadata<T extends Object>(PluginDataKey<T> key, T value);
}

/// Captures a declaration once, so runtime field ownership cannot drift.
final class ComposerMetadataBinding {
  ComposerMetadataBinding({
    required this.codec,
    required Set<String> createWireFields,
    required this.initialMetadata,
    required this.reconcileMetadata,
    required this.createPayload,
    required this.labels,
  }) : createWireFields = Set.unmodifiable(createWireFields);

  final PluginDataPersistenceCodec<Object> codec;
  final Set<String> createWireFields;
  final Object Function(PluginComposerContext) initialMetadata;
  final Object Function(PluginComposerContext, PluginComposerContext, Object)
  reconcileMetadata;
  final Map<String, Object?> Function(PluginComposerContext, Object)
  createPayload;
  final PluginComposerLabels? Function(PluginComposerContext, Object) labels;
}

const composerCoreCreateFields = <String>{
  'title',
  'raw',
  'category',
  'tags',
  'archetype',
  'target_recipients',
  'typing_duration_msecs',
  'composer_open_duration_msecs',
  'draft_key',
  'nested_post',
  'topic_id',
  'reply_to_post_number',
  'whisper',
  'api_key',
  'client_id',
  'user_api_key',
  'user_api_client_id',
  'username',
  'user_id',
};

Map<String, Object?> freezeComposerCreateFields(
  Map<String, Object?> fields, {
  Set<String>? allowed,
}) {
  for (final name in fields.keys) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name) ||
        composerCoreCreateFields.contains(name) ||
        (allowed != null && !allowed.contains(name))) {
      throw ArgumentError('Unowned or reserved composer field $name');
    }
  }
  final frozen = freezeJson(fields);
  if (!frozen.valid) throw const FormatException('Invalid composer payload');
  return frozen.value! as Map<String, Object?>;
}
