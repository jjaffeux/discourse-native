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
      title: 'Unattributed quote',
      description: 'Quoted prose can omit an attribution header.',
      states: const ['No attribution'],
      code: 'DQuote(child: Text("Quoted content"))',
      builder: (_) => const DQuote(child: Text('Quoted content.')),
    ),
  ],
);
