import 'styleguide_example.dart';

/// App-specific compositions of the Native kit, separate from the upstream
/// component reference catalogue.
const applicationComponentCatalogue = <ComponentReference>[
  ComponentReference(
    id: 'notification-level-menu',
    name: 'Notification level menu',
    sections: [
      'Topic notifications',
      'Icon trigger',
      'Category notifications',
      'Thread notifications',
      'Disabled',
    ],
  ),
  ComponentReference(
    id: 'category-selector',
    name: 'Category selector',
    sections: [
      'Filter categories',
      'Composer categories',
      'Category removal',
      'Disabled',
    ],
  ),
  ComponentReference(
    id: 'tag-selector',
    name: 'Tag selector',
    sections: ['Filter tags', 'Composer tags', 'Disabled'],
  ),
];
