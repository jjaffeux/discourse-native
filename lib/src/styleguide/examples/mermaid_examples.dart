import 'package:discourse_native/discourse_ui.dart';

import '../styleguide_example.dart';

const mermaidSamples = <String, String>{
  'Flowchart':
      'flowchart TD\n    A[Write a post] --> B{Ready?}\n    B -->|Yes| C[Share it]\n    B -->|No| A',
  'Sequence':
      'sequenceDiagram\n    Alice->>Bob: Hello!\n    Bob-->>Alice: Welcome back.',
  'Gantt':
      'gantt\n    title Release plan\n    dateFormat YYYY-MM-DD\n    section Work\n    Design :a1, 2026-09-01, 5d\n    Build :after a1, 8d',
  'Class':
      'classDiagram\n    Animal <|-- Duck\n    Animal : +int age\n    Duck : +swim()',
  'State':
      'stateDiagram-v2\n    [*] --> Draft\n    Draft --> Published\n    Published --> [*]',
  'Entity relationship':
      'erDiagram\n    USER ||--o{ POST : writes\n    USER { int id }\n    POST { int id }',
  'Pie': 'pie title Community\n    "Readers" : 70\n    "Writers" : 30',
  'Mindmap':
      'mindmap\n    root((Community))\n      Read\n      Discuss\n      Share',
  'Timeline': 'timeline\n    title Project\n    2025 : Idea\n    2026 : Launch',
  'Git graph':
      'gitGraph\n    commit\n    branch feature\n    checkout feature\n    commit\n    checkout main\n    merge feature',
  'Journey':
      'journey\n    title A visit\n    section Forum\n    Read: 5: Alice\n    Reply: 4: Alice',
  'Markdown labels':
      'flowchart LR\n    A["`**Bold** and *italic*`"] --> B["Unicode: café 日本語"]',
  'Invalid syntax': 'flowchart\n    A -',
};

final mermaidExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Offline diagrams with source access and an expanded view.',
  notes:
      'Uses bundled Mermaid 11.15.0 in a temporary, network-blocked WebView. '
      'The result is a Flutter image; normal scrolling remains with its parent. '
      'Expand enables pinch/drag and keyboard-accessible zoom buttons; arrow keys pan. '
      'Native SVG labels replace HTML labels. Diagram links are inactive. '
      'Syntax errors retain View source and Copy source. '
      'Rendering follows light/dark mode, bounds images to four million pixels, '
      'and keeps a bounded memory cache. Diagram typography scales with zoom.',
  examples: [
    for (final name in ['Flowchart', 'Sequence', 'Gantt', 'Invalid syntax'])
      StyleguideExample(
        title: name,
        description: name == 'Invalid syntax'
            ? 'An invalid diagram preserves its source and displays a controlled error.'
            : 'Expand the diagram, zoom, pan, and inspect or copy its source.',
        states: const ['Light', 'Dark', 'Narrow', 'Keyboard', 'RTL'],
        code: "DMermaid(source: '''\n${mermaidSamples[name]}\n''')",
        builder: (_) => DMermaid(source: mermaidSamples[name]!),
      ),
  ],
);
