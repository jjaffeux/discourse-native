import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final quoteExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'A shared rounded quote for posts, chat, and the composer.',
  notes:
      'Attribution and source navigation remain app-owned. The inset '
      'leading rail is decorative. Native actions may occupy the trailing '
      'slot. Quotes use the raised surface and a decorative quote mark, '
      'and follow reading direction and inherited text scaling.',
  examples: [
    StyleguideExample(
      title: 'Attributed quote',
      description:
          'One rounded surface joins the attribution and multiple paragraphs.',
      states: const ['Attribution', 'Multiline', 'RTL'],
      code: 'DQuote(header: Text("Source"), child: Text("Quoted content"))',
      builder: (_) => const DQuote(
        header: Text('Source attribution'),
        child: Text(
          'The first paragraph stays with its source.\n\n'
          'A second paragraph shares the same leading rail.',
        ),
      ),
    ),
    StyleguideExample(
      title: 'Nested quote',
      description: 'Nested quotes use a compact inset without card padding.',
      states: const ['Nested', 'Multiline', 'RTL'],
      code: 'DQuote(child: DQuote(child: Text("Nested content")))',
      builder: (_) => const DQuote(
        header: Text('Outer source'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('The surrounding quote retains its reading space.'),
            SizedBox(height: 12),
            DQuote(
              header: Text('Nested source'),
              child: Text('The nested quote adds only a small indentation.'),
            ),
            SizedBox(height: 12),
            Text('The outer quote continues here.'),
          ],
        ),
      ),
    ),
    StyleguideExample(
      title: 'Unattributed quote',
      description: 'Quoted prose can omit an attribution header.',
      states: const ['No attribution'],
      code: 'DQuote(child: Text("Quoted content"))',
      builder: (_) => const DQuote(child: Text('Quoted content.')),
    ),
  ],
);
