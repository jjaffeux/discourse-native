import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/l10n/strings.dart';

import 'event_composer_parser.dart';
import 'event_data.dart';

ComposerSyntaxKind get eventSyntaxKind => ComposerSyntaxKind(
  owner: eventsPluginId,
  name: 'event',
  label: appL10n.event,
);

abstract interface class EventAuthoringPolicy implements ComposerSyntaxPolicy {
  bool get firstPost;
}

final class EventSubmitPreparer implements PluginComposerSubmitPreparer {
  const EventSubmitPreparer();
  @override
  PluginComposerSubmitPreparation prepareComposerSubmit(
    ComposerEditorHost composer,
  ) {
    final policy = composer.syntaxPolicy<EventAuthoringPolicy>(eventSyntaxKind);
    final blocks = parseEventBlocks(composer.value.text);
    if (blocks.isNotEmpty && (blocks.length > 1 || policy?.firstPost != true)) {
      return PluginComposerSubmitPreparation.failed(
        WriteException(
          WriteFailure.validation,
          errors: [appL10n.anEventMustBeTheOnlyEventInTheFirstPost],
        ),
      );
    }
    return const PluginComposerSubmitPreparation.proceed();
  }
}
