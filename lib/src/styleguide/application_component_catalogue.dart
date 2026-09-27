import 'styleguide_example.dart';

/// App-specific compositions of the Native kit, separate from the upstream
/// component reference catalogue.
const applicationComponentCatalogue = <ComponentReference>[
  ComponentReference(
    id: 'control-wrap',
    name: 'Control wrap',
    sections: ['Compact controls'],
  ),
  ComponentReference(
    id: 'audio-player',
    name: 'Audio player',
    sections: ['Playback', 'Loading', 'Unavailable'],
  ),
  ComponentReference(
    id: 'embed',
    name: 'Embed',
    sections: ['Embedded content', 'Provider card', 'Unavailable embed'],
  ),
  ComponentReference(
    id: 'onebox',
    name: 'Onebox',
    sections: ['Browse oneboxes'],
  ),
  ComponentReference(
    id: 'drag',
    name: 'Drag',
    sections: ['Drag and tap', 'Disabled'],
  ),
  ComponentReference(
    id: 'history-transition',
    name: 'History transition',
    sections: ['Back and forward', 'RTL'],
  ),
  ComponentReference(
    id: 'page-surface',
    name: 'Page surface',
    sections: ['Page structure'],
  ),
  ComponentReference(
    id: 'sticky',
    name: 'Sticky',
    sections: ['Bounded avatars'],
  ),
  ComponentReference(
    id: 'color-picker',
    name: 'Color picker',
    sections: ['Live color', 'Disabled'],
  ),
  ComponentReference(
    id: 'pull-to-refresh',
    name: 'Pull to refresh',
    sections: ['Topics', 'Short list', 'Empty list', 'Disabled'],
  ),
  ComponentReference(
    id: 'code-editor',
    name: 'Code editor',
    sections: ['Editable code', 'Read-only code'],
  ),
  ComponentReference(
    id: 'mermaid',
    name: 'Mermaid',
    sections: [
      'Composer editor',
      'Flowchart',
      'Sequence',
      'Gantt',
      'Invalid syntax',
    ],
  ),
  ComponentReference(
    id: 'image-preview',
    name: 'Image preview',
    sections: ['Post image', 'Chat image', 'Narrow and disabled'],
  ),
  ComponentReference(
    id: 'notification-dot',
    name: 'Notification dot',
    sections: ['Inline states', 'Header overlay', 'Surface rings'],
  ),
  ComponentReference(
    id: 'message-inbox-menu',
    name: 'Message inbox menu',
    sections: [
      'Personal and groups',
      'Filter row',
      'Group inbox',
      'Personal only',
      'Many groups',
      'Disabled',
    ],
  ),
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
