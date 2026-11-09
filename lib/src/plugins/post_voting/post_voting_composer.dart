import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'post_voting_data.dart';

const postVotingComposerKey = PluginDataKey<PostVotingComposerChoice>(
  owner: 'discourse-post-voting',
  name: 'composer',
);

final class PostVotingComposerChoice {
  const PostVotingComposerChoice(this.choice);
  final bool? choice;
}

final class PostVotingComposerCodec
    extends PluginDataPersistenceCodec<PostVotingComposerChoice> {
  const PostVotingComposerCodec();
  @override
  PluginDataKey<PostVotingComposerChoice> get key => postVotingComposerKey;
  @override
  PostVotingComposerChoice? decode(Object? value) =>
      value is Map && (value['choice'] == null || value['choice'] is bool)
      ? PostVotingComposerChoice(value['choice'] as bool?)
      : null;
  @override
  Object encode(PostVotingComposerChoice value) => {'choice': value.choice};
}

final class PostVotingComposerPlugin
    implements
        SitePlugin,
        ComposerMetadataPlugin<PostVotingComposerChoice>,
        ComposerOptionsPlugin {
  const PostVotingComposerPlugin();
  @override
  String get name => postVotingPluginId.value;
  @override
  PluginDataKey<PostVotingComposerChoice> get record => postVotingComposerKey;
  @override
  PluginDataPersistenceCodec<PostVotingComposerChoice>
  get composerMetadataCodec => const PostVotingComposerCodec();
  @override
  Set<String> get createWireFields => const {'create_as_post_voting'};
  bool _eligible(PluginComposerContext context) =>
      context.createsTopic &&
      !context.isEdit &&
      !context.isPrivateMessage &&
      context.siteSettings.get(postVotingSettingsKey)?.enabled == true;
  bool _selected(PluginComposerContext context, PostVotingComposerChoice held) {
    final category = context.categoryData.get(postVotingCategoryKey);
    return category?.requiredOn == true ||
        (held.choice ?? category?.defaultOn ?? false);
  }

  @override
  PostVotingComposerChoice initialMetadata(PluginComposerContext context) =>
      const PostVotingComposerChoice(null);
  @override
  PostVotingComposerChoice reconcileMetadata(
    PluginComposerContext before,
    PluginComposerContext after,
    PostVotingComposerChoice held,
  ) => before.categoryId == after.categoryId && before.siteUrl == after.siteUrl
      ? held
      : const PostVotingComposerChoice(null);
  @override
  Map<String, Object?> createPayload(
    PluginComposerContext context,
    PostVotingComposerChoice held,
  ) => _eligible(context) && _selected(context, held)
      ? const {'create_as_post_voting': true}
      : const {};
  @override
  PluginComposerLabels? labels(
    PluginComposerContext context,
    PostVotingComposerChoice held,
  ) {
    if (_eligible(context) && _selected(context, held)) {
      return PluginComposerLabels(
        title: appL10n.postVotingCreateTopic,
        submit: appL10n.postVotingCreateTopic,
      );
    }
    if (!context.createsTopic &&
        !context.isEdit &&
        !context.isPrivateMessage &&
        context.siteSettings.get(postVotingSettingsKey)?.enabled != false &&
        context.topicData.get(postVotingTopicKey)?.enabled == true) {
      return PluginComposerLabels(
        title: appL10n.answer,
        submit: appL10n.answer,
      );
    }
    return null;
  }

  @override
  List<Widget> composerOptions(
    BuildContext context,
    ComposerEditorHost editor,
  ) {
    if (!editor.isCurrent) return const [];
    final metadata = editor.metadataContext;
    if (!_eligible(metadata) ||
        metadata.categoryData.get(postVotingCategoryKey)?.requiredOn == true) {
      return const [];
    }
    final held = editor.metadata(context, postVotingComposerKey);
    if (held == null) return const [];
    return [
      DDropdownMenuCheckboxItem(
        checked: _selected(metadata, held),
        closeOnSelect: true,
        onChanged: editor.isEditing
            ? (value) => editor.updateMetadata(
                context,
                postVotingComposerKey,
                PostVotingComposerChoice(value),
              )
            : null,
        child: Text(context.l10n.postVotingCreationToggle),
      ),
    ];
  }
}
