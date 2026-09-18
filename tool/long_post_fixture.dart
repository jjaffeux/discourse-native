// Deterministic offline technical discussion: varied prose and rich structure.
String variedLongPostHtml() {
  final result = StringBuffer();
  final subjects = [
    'cache invalidation',
    'keyboard navigation',
    'database migrations',
    'image uploads',
    'localization',
    'accessibility',
    'plugin compatibility',
    'scroll restoration',
  ];
  for (var i = 0; i < 90; i++) {
    final subject = subjects[i % subjects.length];
    result.write('<h3>Finding ${i + 1}: $subject</h3>');
    result.write(
      '<p>During review $i, we compared <strong>$subject</strong> across desktop and mobile. '
      'The result depends on the current configuration, the amount of retained data, and whether a previous request has completed. '
      'See <a href="https://example.invalid/review/$i">the detailed investigation $i</a> for the recorded observations.</p>',
    );
    result.write(
      '<p>A separate participant reproduced case ${i * 7} with <em>different settings</em>. '
      'Their notes include café, 日本語, and non-breaking&nbsp;spaces. '
      'The proposed change preserves existing behavior while reducing work that repeats for each item.</p>',
    );
    switch (i % 6) {
      case 0:
        result.write(
          '<ul><li>Verify requirement $i with the default configuration.</li><li>Repeat after <strong>editing</strong> item ${i + 3}.<ul><li>Keep the original position.</li></ul></li><li>Check the final result.</li></ul>',
        );
      case 1:
        result.write(
          '<blockquote><p>The previous report for $subject was incomplete.</p><p>Record both the successful and failed attempts.</p></blockquote>',
        );
      case 2:
        result.write(
          '<pre><code class="lang-text">case_$i:\n  input = ${i * 17}\n  expected = preserve_order\n</code></pre>',
        );
      case 3:
        result.write(
          '<div style="padding: 4px; border-left: 2px solid #888"><p>Additional context $i: <span style="font-weight: bold">Keep this container intact.</span> Its descendants inherit their formatting.</p></div>',
        );
      case 4:
        result.write(
          '<ol start="${i + 1}"><li>Load the saved configuration.</li><li>Compare <code>revision_$i</code> with the previous result.</li></ol>',
        );
      case 5:
        result.write(
          '<p>Outcome $i:<br>the initial observation was confirmed.<br>Follow-up work remains independently tracked.</p><hr>',
        );
    }
  }
  return result.toString();
}
