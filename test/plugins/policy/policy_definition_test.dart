import 'package:discourse_native/src/plugins/policy/policy_definition.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const codec = PolicySourceCodec();
void main() {
  test(
    'policy definitions combine legacy audiences and preserve opaque versions',
    () {
      final definition = PolicyDefinition.fromAttributes(const {
        'group': 'team',
        'groups': 'staff,team',
        'version': 'release-2',
        'renew': 'quarterly',
        'renew-start': '2027-01-01',
        'reminder': 'weekly',
        'accept': 'I accept',
        'revoke': 'Undo',
        'private': 'true',
        'add-users-to-group': 'graduates',
      });
      expect(definition.audienceGroups, ['team', 'staff']);
      expect(definition.version, 'release-2');
      expect(
        (definition.renewal as PolicyRenewByCalendar).interval,
        PolicyCalendarInterval.quarterly,
      );
      expect(definition.reminder, PolicyReminder.weekly);
      expect(definition.privateStatistics, isTrue);
      expect(definition.targetGroup, 'graduates');
      expect(definition.renewStartDate, '2027-01-01');
      expect(() => definition.audienceGroups.clear(), throwsUnsupportedError);
      expect(
        PolicyDefinition.fromCookedAttributes(const {
          'class': 'policy',
          'data-group': 'team',
          'data-renew': '90',
        }).renewal,
        isA<PolicyRenewAfterDays>().having((r) => r.days, 'days', 90),
      );
    },
  );
  test('source finder excludes code, quotes and invalid block positions', () {
    const source = '''> [policy groups=quoted]
> Quoted
> [/policy]
[quote="alice"]
[policy groups=quoted]
Quoted
[/policy]
[/quote]
```
[policy groups=fenced]
Code
[/policy]
```
    [policy groups=indented]
    Code
    [/policy]
Inline `[policy groups=inline]`.
[code]
[policy groups=code]
Code
[/policy]
[/code]
<blockquote>
[policy groups=htmlquote]
Quoted
[/policy]
</blockquote>
[policy group='team' groups="staff,team" version=release-2 renew=quarterly reminder=weekly private=true mystery='leave me']
**Real policy**
[/policy]
''';
    final found = codec.find(source);
    expect(found, hasLength(1));
    final block = found.single;
    expect(block.definition.audienceGroups, ['team', 'staff']);
    expect(block.definition.version, 'release-2');
    expect(block.body, '\n**Real policy**\n');
    expect(block.range.textInside(source), block.source);
    expect(
      block.openingTagRange.textInside(source),
      startsWith("[policy group='team'"),
    );
    expect(block.preservedAttributes['mystery'], 'leave me');
  });
  test(
    'settings edit changes exact attribute while preserving all other source',
    () {
      const source =
          "Before\r\n[policy group='team' version=release-2 mystery='leave me' renew=monthly]\r\n**Body**\r\n[/policy]\r\nAfter";
      final block = codec.find(source).single;
      final replacement = PolicyDefinition.fromAttributes({
        ...block.preservedAttributes,
        'version': 'release-3',
      });
      final updated = codec.replaceSettings(
        document: const TextEditingValue(text: source),
        occurrence: block,
        replacement: replacement,
      );
      expect(
        updated.text,
        source.replaceFirst('version=release-2', 'version="release-3"'),
      );
      expect(
        codec
            .replaceSettings(
              document: const TextEditingValue(text: source),
              occurrence: block,
              replacement: block.definition,
            )
            .text,
        source,
      );
      expect(
        () => codec.replaceSettings(
          document: const TextEditingValue(text: 'Changed'),
          occurrence: block,
          replacement: replacement,
        ),
        throwsStateError,
      );
    },
  );
  test('unchanged settings preserve selection and active composition', () {
    const source = '[policy group=team]\nText\n[/policy]';
    const document = TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: 25),
      composing: TextRange(start: 21, end: 25),
    );
    final block = codec.find(source).single;
    expect(
      codec.replaceSettings(
        document: document,
        occurrence: block,
        replacement: block.definition,
      ),
      document,
    );
  });
  test(
    'changed audience migrates legacy group without retaining obsolete members',
    () {
      const source =
          '[policy group=old groups=staff version=1]\nText\n[/policy]';
      final block = codec.find(source).single;
      final updated = codec.replaceSettings(
        document: const TextEditingValue(text: source),
        occurrence: block,
        replacement: PolicyDefinition(audienceGroups: const ['new']),
      );
      expect(updated.text, '[policy groups="new" version=1]\nText\n[/policy]');
      expect(codec.find(updated.text).single.definition.audienceGroups, [
        'new',
      ]);
    },
  );
  test(
    'unsupported known attributes survive unrelated edit but can be explicitly cleared',
    () {
      const source =
          '[policy groups=team renew=future reminder=hourly custom=abc]\nText\n[/policy]';
      final block = codec.find(source).single;
      final updated = codec.replaceSettings(
        document: const TextEditingValue(text: source),
        occurrence: block,
        replacement: PolicyDefinition(
          audienceGroups: const ['team'],
          version: '2',
        ),
      );
      expect(updated.text, contains('renew=future reminder=hourly custom=abc'));
      final cleared = codec.replaceAttributes(
        document: const TextEditingValue(text: source),
        occurrence: block,
        changes: {'reminder': null, 'renew': null},
      );
      expect(cleared.text, '[policy groups=team custom=abc]\nText\n[/policy]');
    },
  );
  test(
    'quoted labels round trip with brackets and both ordinary quotation marks',
    () {
      final definition = PolicyDefinition(
        audienceGroups: const ['team'],
        acceptLabel: 'I accept "this" and \'that\' [policy]',
      );
      final source = '${codec.openingTag(definition)}\nText\n[/policy]';
      expect(
        codec.find(source).single.definition.acceptLabel,
        definition.acceptLabel,
      );
      expect(() => policyMarkupValue('line\nbreak'), throwsFormatException);
    },
  );
  test(
    'bare attributes gain equals when assigned and apostrophes remain valid unquoted text',
    () {
      const source =
          "[policy groups=team version private accept=don't]\nText\n[/policy]";
      final block = codec.find(source).single;
      expect(block.definition.acceptLabel, "don't");
      final updated = codec.replaceAttributes(
        document: const TextEditingValue(text: source),
        occurrence: block,
        changes: const {'version': '4', 'private': 'true'},
      );
      expect(
        updated.text,
        "[policy groups=team version=\"4\" private=\"true\" accept=don't]\nText\n[/policy]",
      );
      expect(
        codec.find(updated.text).single.definition.privateStatistics,
        isTrue,
      );
    },
  );
  test('incomplete, nested, duplicate or groupless blocks remain raw', () {
    for (final source in [
      '[policy groups=team]\nunfinished',
      '[policy]\nText\n[/policy]',
      '[policy groups=team groups=other]\nText\n[/policy]',
      '[policy groups="team]\nText\n[/policy]',
      '[policy groups=team] trailing\nText\n[/policy]',
      '[policy groups=team]\n[policy groups=other]\nText\n[/policy]\n[/policy]',
    ]) {
      expect(codec.find(source), isEmpty, reason: source);
    }
  });
  test('code and quoted closing tags cannot truncate a real policy body', () {
    const source =
        '[policy groups=team]\n```\n[/policy]\n```\n> [/policy]\nText\n[/policy]';
    final block = codec.find(source).single;
    expect(block.body, contains('Text'));
    expect(block.end, source.length);
  });
}
