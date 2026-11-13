import '../../plugin_api/composer_syntax.dart';
import 'markdown_editing_controller.dart';

abstract interface class ComposerComponentEditingHost
    implements ComposerEditorHost {
  MarkdownEditingController get text;
  void dismissAutocomplete();
}
