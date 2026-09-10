import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/topic_list_filter_bar.dart';
import 'package:discourse_native/src/styleguide/examples/combobox_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

// Local data only; mounts the production filters alongside the kit example.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _Review());
}

const _categories = [
  TopicCategory(id: 1, name: 'sales', color: 'ED2084'),
  TopicCategory(id: 2, parentCategoryId: 1, name: 'deals', color: '0095CC'),
  TopicCategory(id: 3, parentCategoryId: 1, name: 'leads', color: 'E5B92E'),
  TopicCategory(id: 4, name: 'general', color: '29AAD7'),
  TopicCategory(id: 5, name: 'Support and product feedback', color: '348848'),
  TopicCategory(id: 6, name: 'todo', color: 'CD48B7'),
  TopicCategory(id: 7, name: 'sysadmin', color: 'F49A16'),
  TopicCategory(id: 8, name: 'legal', color: 'BB1D30'),
  TopicCategory(id: 9, name: 'code review', color: '29AAD7'),
];
const _tags = [
  SidebarTag(id: 1, name: 'pri-medium', slug: 'pri-medium'),
  SidebarTag(id: 2, name: 'pri-high', slug: 'pri-high'),
  SidebarTag(id: 3, name: 'pri-urgent', slug: 'pri-urgent'),
  SidebarTag(id: 4, name: 'approved', slug: 'approved'),
  SidebarTag(id: 5, name: 'commit', slug: 'commit'),
  SidebarTag(id: 6, name: 'runbook-authored', slug: 'runbook-authored'),
  SidebarTag(id: 7, name: 'vuln-status-create', slug: 'vuln-status-create'),
  SidebarTag(id: 8, name: 'auto-generated', slug: 'auto-generated'),
];

class _Review extends StatefulWidget {
  const _Review();

  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool _dark = true;
  bool _narrow = false;
  bool _rtl = false;
  double _scale = 1;
  int? _category = 2;
  List<String> _selectedTags = [];

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _dark ? AppTheme.dark : AppTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(_scale)),
      child: Directionality(
        textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
    ),
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DButton(
                    label: Text(_dark ? 'Light palette' : 'Dark palette'),
                    onPressed: () => setState(() => _dark = !_dark),
                  ),
                  DButton(
                    label: Text(_narrow ? 'Wide layout' : 'Narrow layout'),
                    onPressed: () => setState(() => _narrow = !_narrow),
                  ),
                  DButton(
                    label: Text(_scale == 1 ? '200% text' : '100% text'),
                    onPressed: () =>
                        setState(() => _scale = _scale == 1 ? 2 : 1),
                  ),
                  DButton(
                    label: const Text('RTL / LTR'),
                    onPressed: () => setState(() => _rtl = !_rtl),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Topic filters'),
              const SizedBox(height: 12),
              SizedBox(
                width: _narrow ? 320 : 680,
                child: TopicListFilterBar(
                  inline: true,
                  wrap: _narrow,
                  siteUrl: 'https://topic-filters.invalid',
                  categories: _categories,
                  knownTags: _tags,
                  selectedCategoryId: _category,
                  selectedTagName: _selectedTags.firstOrNull,
                  selectedTagNames: _selectedTags,
                  taggingEnabled: true,
                  searchTags: (query) async {
                    await Future<void>.delayed(
                      const Duration(milliseconds: 300),
                    );
                    if (query == 'fail') {
                      throw StateError('Fixture lookup failed');
                    }
                    return query == 'remote'
                        ? const [TopicFilterLookupValue(name: 'remote-tag')]
                        : const [];
                  },
                  onCategorySelected: (category) =>
                      setState(() => _category = category?.id),
                  onTagSelected: (_) {},
                  onTagsSelected: (tags) =>
                      setState(() => _selectedTags = tags),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Category: ${_category ?? 'all'} · Tags: ${_selectedTags.isEmpty ? 'all' : _selectedTags.join(', ')}',
              ),
              const SizedBox(height: 120),
              const Text('UI kit · Combobox Popup example'),
              const SizedBox(height: 12),
              SizedBox(
                width: 320,
                child: Builder(
                  builder: comboboxExamples.examples
                      .firstWhere((example) => example.title == 'Popup')
                      .builder,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
