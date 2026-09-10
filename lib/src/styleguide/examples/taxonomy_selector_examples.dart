import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../models/topic.dart';
import '../styleguide_example.dart';

const _categories = [
  TopicCategory(
    id: 1,
    name: 'Discourse Native App',
    color: '663399',
    styleType: 'icon',
    icon: 'folder',
    readRestricted: true,
  ),
  TopicCategory(id: 2, name: 'Support', color: '0088CC'),
  TopicCategory(id: 3, name: 'Design', parentCategoryId: 1, color: 'BF3B7B'),
];
const _tags = [
  TopicTag(id: 1, name: 'design', slug: 'design'),
  TopicTag(id: 2, name: 'mobile', slug: 'mobile'),
  TopicTag(id: 3, name: 'accessibility', slug: 'accessibility'),
  TopicTag(
    id: 4,
    name: 'staff',
    disabled: true,
    disabledReason: 'Only staff can use this tag.',
  ),
];

final categorySelectorExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'A category button with its searchable selection dropdown.',
  notes:
      'TopicCategorySelector is the complete component used by the topics list '
      'and composer, as well as topic header and sidebar editing. It composes the '
      'Native Combobox, Button, and category artwork. '
      'Filtering can include All categories; authoring accepts a permission-filtered '
      'asynchronous search and parent-path labels. Search resets on reopen, ignores '
      'retired requests, and supports arrows, Enter, and Escape. Change the widget '
      'key when its account or search scope changes. The composer example accepts '
      '“fail” to show a lookup error. All example data stays local.',
  examples: [
    StyleguideExample(
      title: 'Filter categories',
      description:
          'Search local categories or clear the filter with All categories.',
      states: const ['Selection', 'Search', 'Clear', 'Private category'],
      code: '''TopicCategorySelector(
  siteUrl: siteUrl, categories: categories, selected: selected,
  includeAll: true, onSelected: (value) => setState(() => selected = value),
)''',
      builder: (_) => const _CategoryExample(),
    ),
    StyleguideExample(
      title: 'Composer categories',
      description:
          'Choose a category using asynchronous search and parent paths.',
      states: const ['Async search', 'Subcategory', 'Empty', 'Error'],
      code: '''TopicCategorySelector(
  siteUrl: siteUrl, categories: categories, selected: selected,
  placeholder: 'Choose a category', labelFor: categoryPath,
  search: searchCreatableCategories,
  onSelected: (value) => setState(() => selected = value),
)''',
      builder: (_) => const _CategoryExample(composer: true),
    ),
    StyleguideExample(
      title: 'Category removal',
      description:
          'Keep the removal choice available while searching for a replacement.',
      states: const ['Removal', 'Search', 'Empty'],
      code: '''TopicCategorySelector(
  siteUrl: siteUrl, categories: categories, selected: selected,
  clearLabel: 'Remove subcategory',
  onSelected: (value) => setState(() => selected = value),
)''',
      builder: (_) => const _CategoryExample(removable: true),
    ),
    StyleguideExample(
      title: 'Disabled',
      description: 'A selected category whose value cannot be changed.',
      states: const ['Disabled'],
      code: '''TopicCategorySelector(
  siteUrl: siteUrl, categories: categories, selected: selected,
  onSelected: null,
)''',
      builder: (_) => const _CategoryExample(disabled: true),
    ),
  ],
);

final tagSelectorExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'A tag button with search, selection, and optional tag creation.',
  notes:
      'TopicTagSelector is the complete component used by the topics list and '
      'composer. Both use the same Native Combobox popup, search field, option '
      'rows, and selection indicators. Filters can include All tags and use known '
      'tags if search fails. Composer capabilities enforce disabled tags, creation '
      'rules, and maximum selections; selected tags remain available for removal. '
      'Search invalidates stale results immediately and resets on reopen. Change '
      'the widget key when its account/category scope changes. The composer '
      'example allows two tags and accepts “blocked” to show a server restriction '
      'or “fail” for an error. All example data stays local.',
  examples: [
    StyleguideExample(
      title: 'Filter tags',
      description: 'Choose one known tag or clear the selection with All tags.',
      states: const ['Single selection', 'Search', 'Clear'],
      code: '''TopicTagSelector(
  selectedTags: selected, knownTags: tags, search: searchTags,
  multiple: false, includeAll: true,
  onChanged: (value) => setState(() => selected = value),
)''',
      builder: (_) => const _TagExample(),
    ),
    StyleguideExample(
      title: 'Composer tags',
      description:
          'Add or remove tags, or create a permitted new tag; the limit is two.',
      states: const [
        'Multiple selection',
        'Create',
        'Limit',
        'Disabled option',
        'Error',
      ],
      code: '''TopicTagSelector(
  selectedTags: selected, search: searchTags, placeholder: 'Add tags',
  capabilities: const TopicComposerCapabilities(
    canTagTopics: true, canCreateTag: true, maxTagsPerTopic: 2,
    maxTagLength: 25, tagsFilterRegexp: r'[^a-z0-9-]',
  ),
  onChanged: (value) => setState(() => selected = value),
)''',
      builder: (_) => const _TagExample(composer: true),
    ),
    StyleguideExample(
      title: 'Disabled',
      description: 'Selected tags remain readable when editing is unavailable.',
      states: const ['Disabled'],
      code: '''TopicTagSelector(
  selectedTags: selected, search: searchTags, onChanged: null,
)''',
      builder: (_) => const _TagExample(disabled: true),
    ),
  ],
);

class _CategoryExample extends StatefulWidget {
  const _CategoryExample({
    this.composer = false,
    this.disabled = false,
    this.removable = false,
  });
  final bool composer;
  final bool disabled;
  final bool removable;

  @override
  State<_CategoryExample> createState() => _CategoryExampleState();
}

class _CategoryExampleState extends State<_CategoryExample> {
  TopicCategory? _selected = _categories.first;

  String _path(TopicCategory category) => category.parentCategoryId == null
      ? category.name
      : '${_categories.first.name} / ${category.name}';

  Future<List<TopicCategory>> _search(String query) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (query == 'fail') throw StateError('Local fixture lookup failed');
    return _categories
        .where(
          (category) =>
              _path(category).toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) => TopicCategorySelector(
    siteUrl: 'https://styleguide.invalid',
    categories: _categories,
    selected: _selected,
    placeholder: widget.composer ? 'Choose a category' : 'Categories',
    includeAll: !widget.composer && !widget.removable,
    clearLabel: widget.removable ? 'Remove subcategory' : null,
    labelFor: widget.composer ? _path : null,
    search: widget.composer ? _search : null,
    onSelected: widget.disabled
        ? null
        : (value) => setState(() => _selected = value),
  );
}

class _TagExample extends StatefulWidget {
  const _TagExample({this.composer = false, this.disabled = false});
  final bool composer;
  final bool disabled;

  @override
  State<_TagExample> createState() => _TagExampleState();
}

class _TagExampleState extends State<_TagExample> {
  List<TopicTag> _selected = const [];

  @override
  void initState() {
    super.initState();
    if (widget.disabled || widget.composer) _selected = [_tags.first];
  }

  Future<TopicTagSearch> _search(String query) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (query == 'fail') throw StateError('Local fixture lookup failed');
    if (query == 'blocked') return const TopicTagSearch(forbidden: true);
    return TopicTagSearch(
      tags: _tags
          .where((tag) => tag.name.contains(query.toLowerCase()))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) => TopicTagSelector(
    selectedTags: _selected,
    knownTags: widget.composer ? const [] : _tags,
    search: _search,
    multiple: widget.composer,
    includeAll: !widget.composer,
    placeholder: widget.composer ? 'Add tags' : 'Tags',
    capabilities: widget.composer
        ? const TopicComposerCapabilities(
            canTagTopics: true,
            canCreateTag: true,
            maxTagsPerTopic: 2,
            maxTagLength: 25,
            tagsFilterRegexp: r'[^a-z0-9-]',
          )
        : const TopicComposerCapabilities(),
    onChanged: widget.disabled
        ? null
        : (value) => setState(() => _selected = value),
  );
}
