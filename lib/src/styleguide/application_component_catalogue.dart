import 'styleguide_example.dart';

/// App-specific compositions of the Native kit, separate from the upstream
/// component reference catalogue.
const applicationComponentCatalogue = <ComponentReference>[
  ComponentReference(
    id: 'category-selector',
    name: 'Category selector',
    sections: ['Filter categories', 'Composer categories', 'Disabled'],
  ),
  ComponentReference(
    id: 'tag-selector',
    name: 'Tag selector',
    sections: ['Filter tags', 'Composer tags', 'Disabled'],
  ),
];
