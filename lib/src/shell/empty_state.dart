import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'add_instance_sheet.dart';
import 'forum_theme_surfaces.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: ForumWindowBackground.surfaceColor(
      context,
      Theme.of(context).shell.content,
    ),
    child: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          child: DEmpty(
            children: [
              DEmptyHeader(
                children: [
                  const DEmptyMedia(
                    variant: DEmptyMediaVariant.icon,
                    child: DIcon(DIcons.comments),
                  ),
                  DEmptyTitle(context.l10n.noSitesYet, headingLevel: 1),
                  DEmptyDescription(
                    context.l10n.connectADiscourseForumToGetStarted,
                  ),
                ],
              ),
              DEmptyContent(
                children: [
                  DButton(
                    label: Text(context.l10n.addASite),
                    onPressed: () => showAddInstanceSheet(context),
                    icon: const DIcon(DIcons.plus),
                    variant: DButtonVariant.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
