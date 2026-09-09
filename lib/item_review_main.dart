import 'package:flutter/material.dart';

import 'discourse_ui.dart';
import 'src/macos_launch_screen.dart';
import 'src/models/sidebar_tag.dart';
import 'src/plugins/assign/assignment.dart';
import 'src/plugins/assign/assignment_sheet.dart';
import 'src/shell/tags_page.dart';
import 'src/styleguide/styleguide_page.dart';
import 'src/theme/app_theme.dart';

/// Local-data review runner. No account, stores, API or image requests.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const ItemMigrationFixture(),
    ),
  );
}

class ItemMigrationFixture extends StatefulWidget {
  const ItemMigrationFixture({super.key});
  @override
  State<ItemMigrationFixture> createState() => _ItemMigrationFixtureState();
}

class _ItemMigrationFixtureState extends State<ItemMigrationFixture> {
  String _status = 'Local fixture ready';
  bool _editable = true;
  bool _rtl = false;
  bool _large = false;
  bool _dark = false;
  @override
  Widget build(BuildContext context) => Theme(
    data: _dark ? AppTheme.dark : AppTheme.light,
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: const Text('Item · production fixtures'),
          actions: [
            DButton(
              label: const Text('Styleguide'),
              onPressed: () => showComponentStyleguide(context),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: 160,
                    child: DCheckbox(
                      value: _editable,
                      title: Text(_editable ? 'Editing allowed' : 'Read only'),
                      onChanged: (value) => setState(() => _editable = value!),
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: DCheckbox(
                      value: _rtl,
                      title: Text(_rtl ? 'RTL' : 'LTR'),
                      onChanged: (value) => setState(() => _rtl = value!),
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: DCheckbox(
                      value: _large,
                      title: Text(_large ? '200%' : '100%'),
                      onChanged: (value) => setState(() => _large = value!),
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: DCheckbox(
                      value: _dark,
                      title: Text(_dark ? 'Dark' : 'Light'),
                      onChanged: (value) => setState(() => _dark = value!),
                    ),
                  ),
                ],
              ),
            ),
            Semantics(liveRegion: true, child: Text(_status)),
            Expanded(
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(_large ? 2 : 1),
                  disableAnimations: true,
                ),
                child: Directionality(
                  textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: 448,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: 5,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index < 3) {
                            final tag = [
                              const SidebarTag(
                                id: 1,
                                name: 'development',
                                slug: 'development',
                                count: 42,
                                description:
                                    'Discuss Discourse development and extensions.',
                              ),
                              const SidebarTag(
                                id: 2,
                                name: 'private-team',
                                slug: 'private-team',
                                pmOnly: true,
                                count: 1,
                              ),
                              const SidebarTag(
                                id: 3,
                                name: 'A long tag name for a narrow directory',
                                slug: 'long',
                                count: 12345,
                                description:
                                    'A longer description stays readable at large text and follows the interface direction.',
                              ),
                            ][index];
                            return TagDirectoryRow(
                              tag: tag,
                              onTap: () => setState(
                                () => _status = 'Opened tag ${tag.slug}',
                              ),
                            );
                          }
                          return AssignmentDetailRow(
                            key: ValueKey('fixture-assignment-$index'),
                            assignment: Assignment(
                              assignee: index == 3
                                  ? const AssignmentUser(
                                      username: 'sam',
                                      name: 'Sam',
                                    )
                                  : const AssignmentGroup(name: 'team'),
                              status: 'In progress',
                              note:
                                  'Retain the complete assignment note.\nFollow up with the team after the release.\nThis third line must remain visible.',
                            ),
                            targetLabel: index == 3 ? 'Topic' : 'Post #7',
                            onTap: _editable
                                ? () => setState(
                                    () => _status =
                                        'Edit assignment ${index - 2}',
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
