import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../shell/composer_controller.dart';
import '../../shell/shell_scope.dart';
import '../../theme/d_icons.dart';
import '../site_plugin.dart';
import 'local_date_composer_editor.dart';
import 'local_date_composer_parser.dart';
import 'local_date_composer_sheet.dart';
import 'local_date_environment.dart';

class LocalDatesPlugin implements SitePlugin, ComposerToolbarPlugin {
  const LocalDatesPlugin();

  @override
  String get name => 'discourse-local-dates';

  @override
  List<ComposerToolbarContribution> composerToolbar(
    BuildContext context,
    ComposerController composer,
  ) {
    final controller = ShellScope.maybeRead(context);
    if (controller == null ||
        composer.loadingBody ||
        !controller.siteConfigFor(composer.target.siteUrl).localDatesEnabled) {
      return const [];
    }
    return [
      ComposerToolbarContribution(
        icon: DIcons.farClock,
        label: 'Insert date/time  ⇧.',
        onInvoke: () => unawaited(openLocalDateComposer(context, composer)),
      ),
    ];
  }
}

Future<void> openLocalDateComposer(
  BuildContext context,
  ComposerController composer, {
  LocalDateComposerBlock? block,
}) async {
  final controller = ShellScope.maybeRead(context);
  if (controller == null ||
      !identical(controller.visibleComposer, composer) ||
      (block == null &&
          !controller
              .siteConfigFor(composer.target.siteUrl)
              .localDatesEnabled)) {
    return;
  }
  final expectedDocument = composer.text.text;
  final expectedSelection = composer.text.selection;
  final environment = LocalDateEnvironment.instance;
  final accountTimezone = controller
      .currentUserFor(composer.target.siteUrl)
      ?.timezone;
  final sourceTimezone = environment.readerTimezone(accountTimezone);
  final location = environment.location(sourceTimezone)!;
  final wallNow = tz.TZDateTime.from(DateTime.now(), location);
  final draft = block == null
      ? LocalDateComposerDraft.newDate(now: wallNow, timezone: sourceTimezone)
      : LocalDateComposerDraft.fromBlock(block);

  bool stillCurrent() =>
      context.mounted &&
      identical(ShellScope.maybeRead(context), controller) &&
      identical(controller.visibleComposer, composer) &&
      composer.text.text == expectedDocument;

  final action = await showLocalDateComposerSheet(
    context: context,
    draft: draft,
    siteFormats: controller
        .siteConfigFor(composer.target.siteUrl)
        .localDateFormats,
    isCurrent: stillCurrent,
  );
  if (action == null || !context.mounted) return;
  if (!stillCurrent()) {
    _message(
      context,
      'The composer changed while this date was open. Nothing was changed.',
    );
    return;
  }
  final LocalDateComposerMutation mutation;
  switch (action.type) {
    case LocalDateComposerSheetActionType.apply:
      final replacement = action.draft!.serialize();
      if (block != null && replacement == block.source) {
        composer.focus.requestFocus();
        return;
      }
      mutation = block == null
          ? insertVerifiedLocalDate(
              current: composer.text.value,
              expectedDocument: expectedDocument,
              expectedSelection: expectedSelection,
              markup: replacement,
            )
          : replaceVerifiedLocalDate(
              current: composer.text.value,
              expectedDocument: expectedDocument,
              expectedBlock: block,
              replacement: replacement,
            );
    case LocalDateComposerSheetActionType.remove:
      if (block == null) return;
      mutation = removeVerifiedLocalDate(
        current: composer.text.value,
        expectedDocument: expectedDocument,
        expectedBlock: block,
      );
  }
  if (!mutation.applied) {
    _message(context, mutation.message!);
    return;
  }
  composer.text.value = mutation.value;
  composer.focus.requestFocus();
}

void removeLocalDateComposer(
  BuildContext context,
  ComposerController composer,
  LocalDateComposerBlock block,
) {
  final controller = ShellScope.maybeRead(context);
  if (controller == null || !identical(controller.visibleComposer, composer)) {
    return;
  }
  final expectedDocument = composer.text.text;
  final mutation = removeVerifiedLocalDate(
    current: composer.text.value,
    expectedDocument: expectedDocument,
    expectedBlock: block,
  );
  if (!mutation.applied) {
    _message(context, mutation.message!);
    return;
  }
  composer.text.value = mutation.value;
  composer.focus.requestFocus();
}

void insertCurrentLocalDate(
  BuildContext context,
  ComposerController composer, {
  DateTime? now,
}) {
  final controller = ShellScope.maybeRead(context);
  if (controller == null ||
      !identical(controller.visibleComposer, composer) ||
      !controller.siteConfigFor(composer.target.siteUrl).localDatesEnabled) {
    return;
  }
  final environment = LocalDateEnvironment.instance;
  final timezone = environment.readerTimezone(
    controller.currentUserFor(composer.target.siteUrl)?.timezone,
  );
  final wall = tz.TZDateTime.from(
    now ?? DateTime.now(),
    environment.location(timezone)!,
  );
  final draft = LocalDateComposerDraft.newDate(now: wall, timezone: timezone)
      .copyWith(
        startTime:
            '${wall.hour.toString().padLeft(2, '0')}:'
            '${wall.minute.toString().padLeft(2, '0')}:'
            '${wall.second.toString().padLeft(2, '0')}',
      );
  final mutation = insertVerifiedLocalDate(
    current: composer.text.value,
    expectedDocument: composer.text.text,
    expectedSelection: composer.text.selection,
    markup: draft.serialize(),
  );
  if (!mutation.applied) return;
  composer.text.value = mutation.value;
  composer.focus.requestFocus();
}

void _message(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}
