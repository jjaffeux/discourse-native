import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'add_instance_sheet.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).shell.content,
    child: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          child: DEmpty(
            children: [
              const DEmptyHeader(
                children: [
                  DEmptyMedia(
                    variant: DEmptyMediaVariant.icon,
                    child: DIcon(DIcons.comments),
                  ),
                  DEmptyTitle('No sites yet', headingLevel: 1),
                  DEmptyDescription(
                    'Connect a Discourse forum to get started.',
                  ),
                ],
              ),
              DEmptyContent(
                children: [
                  DButton(
                    label: const Text('Add a site'),
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
