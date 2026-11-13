import '../../../plugin_api/composer_syntax.dart';
import '../controller.dart';
import 'code.dart';
import 'details.dart';
import 'list_policy.dart';
import 'table.dart';
import 'upload.dart';
import 'video.dart';

List<ComposerSyntaxPolicy> coreComposerSyntaxPolicies(
  ComposerController composer,
) => [
  if (!composer.target.isPlugin) ...[
    ComposerUploadPlaceholderPolicy(
      findSlots: (source) => composer.uploadPlaceholders.find(source),
      renderUpload: (context, id) => composer.artwork.upload(
        key: context.pillKey,
        composer: composer,
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
        composer: composer,
        table: table,
        highlighted: context.highlighted,
      ),
    ),
    ComposerCodePolicy(
      composer,
      (context, block, onSelect) => composer.artwork.codeBlock(
        key: context.pillKey,
        composer: composer,
        block: block,
        highlighted: context.highlighted,
        onSelect: onSelect,
      ),
    ),
    ComposerDetailsPolicy(
      composer,
      (context, block) => composer.artwork.details(
        key: context.pillKey,
        composer: composer,
        block: block,
        highlighted: context.highlighted,
      ),
    ),
    ComposerListPolicy(
      composer,
      embeddedInList: composer.singleNewlineParagraphs,
      render: (context, item) => composer.artwork.listItem(
        key: context.pillKey,
        composer: composer,
        item: item,
        highlighted: context.highlighted,
        scrollController: context.scrollController,
      ),
    ),
  ],
];
