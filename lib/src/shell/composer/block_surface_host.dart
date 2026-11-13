import 'block_controller.dart';
import 'history_host.dart';
import 'markdown_editing_controller.dart';

abstract interface class ComposerBlockSurfaceHost
    implements ComposerHistoryHost {
  ComposerBlockController get blocks;
  MarkdownEditingController get text;
}
