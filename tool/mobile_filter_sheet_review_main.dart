import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_list_filter_bar.dart';
import 'package:discourse_native/src/shell/topic_list_navigation.dart';
import 'package:discourse_native/src/styleguide/examples/combobox_examples.dart';
import 'package:discourse_native/src/styleguide/examples/dropdown_menu_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Review());
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
}

class _Review extends StatefulWidget {
  const _Review();
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool dark = false;
  bool mobile = true;
  TopicListMode mode = TopicListMode.latest;
  int? category;
  List<String> tags = [];
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
      platform: mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: DSpacing.controlGap,
                children: [
                  DButton(
                    label: const Text('Theme'),
                    onPressed: () => setState(() => dark = !dark),
                  ),
                  DButton(
                    label: const Text('Platform'),
                    onPressed: () => setState(() => mobile = !mobile),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TopicListFilterBar(
                inline: true,
                siteUrl: '',
                categories: const [
                  TopicCategory(
                    id: 1,
                    name: 'General',
                    color: '0088CC',
                    slug: 'general',
                  ),
                  TopicCategory(
                    id: 2,
                    name: 'Announcements',
                    color: 'BB55CC',
                    slug: 'announcements',
                  ),
                ],
                knownTags: const [
                  SidebarTag(id: 1, name: 'design', slug: 'design'),
                  SidebarTag(id: 2, name: 'flutter', slug: 'flutter'),
                ],
                selectedCategoryId: category,
                selectedTagName: null,
                selectedTagNames: tags,
                taggingEnabled: true,
                searchTags: (_) async => [],
                onCategorySelected: (value) =>
                    setState(() => category = value?.id),
                onTagSelected: (_) {},
                onTagsSelected: (value) => setState(() => tags = value),
                leading: TopicFeedMenu(
                  mode: mode,
                  onSelected: (value) => setState(() => mode = value),
                ),
              ),
              const SizedBox(height: 32),
              const Text('Styleguide: Sheet on mobile'),
              dropdownMenuExamples.examples.last.builder(context),
              comboboxExamples.examples.last.builder(context),
            ],
          ),
        ),
      ),
    ),
  );
}
