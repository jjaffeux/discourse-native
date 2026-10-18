import '../../../plugin_api/composer_syntax.dart';
import '../controller.dart';
import 'code.dart';
import 'details.dart';
import 'list.dart';
import 'table.dart';
import 'upload.dart';
import 'video.dart';

List<ComposerSyntaxPolicy> coreComposerSyntaxPolicies(
  ComposerController composer,
) => [
  if (!composer.target.isPlugin) ...[
    ComposerUploadPlaceholderPolicy(composer),
    const ComposerVideoPolicy(),
    ComposerTablePolicy(composer),
    ComposerCodePolicy(composer),
    ComposerDetailsPolicy(composer),
    ComposerListPolicy(composer),
  ],
];
