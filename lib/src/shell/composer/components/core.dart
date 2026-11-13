import '../../../plugin_api/composer_syntax.dart';
import '../component_artwork.dart';
import '../component_editing_host.dart';
import 'code.dart';
import 'details.dart';
import 'list_policy.dart';
import 'table.dart';
import 'upload.dart';
import 'video.dart';

abstract interface class ComposerPolicyHost<Editor>
    implements ComposerComponentEditingHost {
  ComposerComponentArtwork<Editor> get artwork;
  ComposerUploadPlaceholders get uploadPlaceholders;
  bool get singleNewlineParagraphs;
  void cancelUpload(int id);
}

List<ComposerSyntaxPolicy> coreComposerSyntaxPolicies<Editor>(
  ComposerPolicyHost<Editor> composer,
  Editor artworkOwner,
) => [
  if (!composer.isPluginTarget) ...[
    ComposerUploadPlaceholderPolicy(
      findSlots: (source) => composer.uploadPlaceholders.find(source),
      renderUpload: (context, id) => composer.artwork.upload(
        key: context.pillKey,
        composer: artworkOwner,
        id: id,
        highlighted: context.highlighted,
      ),
      cancelUpload: composer.cancelUpload,
    ),
    ComposerVideoPolicy(
      (context, url, title) => composer.artwork.video(
        key: context.pillKey,
        url: url,
        title: title,
        siteUrl: context.siteUrl,
        highlighted: context.highlighted,
      ),
    ),
    ComposerTablePolicy(
      composer,
      (context, table) => composer.artwork.table(
        key: context.pillKey,
        composer: artworkOwner,
        table: table,
        highlighted: context.highlighted,
      ),
    ),
    ComposerCodePolicy(
      composer,
      (context, block, onSelect) => composer.artwork.codeBlock(
        key: context.pillKey,
        composer: artworkOwner,
        block: block,
        highlighted: context.highlighted,
        onSelect: onSelect,
      ),
    ),
    ComposerDetailsPolicy(
      composer,
      (context, block) => composer.artwork.details(
        key: context.pillKey,
        composer: artworkOwner,
        block: block,
        highlighted: context.highlighted,
      ),
    ),
    ComposerListPolicy(
      composer,
      embeddedInList: composer.singleNewlineParagraphs,
      render: (context, item) => composer.artwork.listItem(
        key: context.pillKey,
        composer: artworkOwner,
        item: item,
        highlighted: context.highlighted,
        scrollController: context.scrollController,
      ),
    ),
  ],
];
