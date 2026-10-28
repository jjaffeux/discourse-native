import 'package:discourse_native/discourse_plugin_sdk.dart' show CookedHtml;
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/widgets.dart';

import 'voice_controller.dart';
import 'voice_models.dart';
import 'voice_room_editor.dart';

Future<void> showVoiceRoomInfo(
  BuildContext context, {
  required String siteUrl,
  required VoiceRoom room,
  required VoiceController controller,
}) async {
  final ownsAccount = controller.captureSiteSession(siteUrl);
  final edit = await showDDialog<bool>(
    context: context,
    builder: (context, dialog) => DDialogContent(
      maxWidth: 520,
      children: [
        DDialogHeader(children: [DDialogTitle(child: Text(room.name))]),
        DDialogScrollArea(
          maxHeightFactor: .6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DSpacing.md,
            children: [
              if (room.cookedDescription case final cooked?
                  when cooked.isNotEmpty)
                CookedHtml(html: cooked, siteUrl: siteUrl)
              else if (room.description case final description?)
                Text(description),
              Wrap(
                spacing: DSpacing.sm,
                runSpacing: DSpacing.sm,
                children: [
                  DBadge(
                    variant: DBadgeVariant.secondary,
                    child: Text(
                      room.isPublic
                          ? context.l10n.publicRoom
                          : context.l10n.private,
                    ),
                  ),
                  if (room.type == VoiceRoomType.stage)
                    DBadge(
                      variant: DBadgeVariant.secondary,
                      child: Text(context.l10n.stageRoom),
                    ),
                ],
              ),
            ],
          ),
        ),
        DDialogFooter(
          children: [
            if (room.canManage)
              DButton(
                label: Text(context.l10n.editRoom),
                onPressed: () => dialog.close(true),
              ),
            DButton(
              label: Text(context.l10n.close),
              variant: DButtonVariant.secondary,
              onPressed: () => dialog.close(false),
            ),
          ],
        ),
      ],
    ),
  );
  if (edit == true && context.mounted && ownsAccount()) {
    await showVoiceRoomEditor(
      context,
      siteUrl: siteUrl,
      room: room,
      controller: controller,
    );
  }
}
