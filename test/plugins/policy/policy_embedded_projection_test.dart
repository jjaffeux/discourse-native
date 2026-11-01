import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/policy/policy_composer.dart';
import 'package:discourse_native/src/plugins/policy/policy_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final state = ComposerPluginState(
    siteSettings: PluginData.none.withValue(
      policySettingsKey,
      const PolicySettings(enabled: true),
    ),
  );
  final policy = PolicyComposerPolicy(
    ComposerSyntaxPolicyContext(
      siteUrl: 'https://example.test',
      isPluginTarget: false,
      isEdit: false,
      initialState: state,
      readState: () => state,
      readEditor: () => throw UnimplementedError(),
    ),
  );
  ComposerEmbeddedDocumentProjection projection(String document) =>
      policy.parse(document).single as ComposerEmbeddedDocumentProjection;

  for (final newline in ['\n', '\r\n']) {
    test(
      'tight empty Policy edits preserve lexemes with ${newline.length}-byte newlines',
      () {
        const opening = '[POLICY group=crew future="keep" version=2]  ';
        const closing = '  [/POLICY]';
        final empty = '$opening$newline$closing';
        final before = 'Before$newline';
        var part = projection('$before$empty');
        expect(
          part.bodyRange.start,
          before.length + opening.length + newline.length,
        );
        expect(part.bodyRange.isCollapsed, isTrue);
        expect(part.replaceBody(''), empty);
        final filled =
            '$opening${newline}first${newline}second$newline$closing';
        expect(part.replaceBody('first\nsecond'), filled);
        part = projection('$before$filled');
        expect(
          part.replaceBody('replacement'),
          '$opening${newline}replacement$newline$closing',
        );
        final cleared = part.replaceBody('');
        expect(cleared, '$opening$newline$newline$closing');
        part = projection('$before$cleared');
        expect(
          part.replaceBody('retyped'),
          '$opening${newline}retyped$newline$closing',
        );
        expect(
          policy.parse('$before${part.replaceBody('[policy groups=other]')}'),
          isEmpty,
        );
      },
    );
  }
}
