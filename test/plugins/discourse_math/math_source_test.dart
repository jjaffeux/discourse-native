import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_math/math_settings.dart';
import 'package:discourse_native/src/plugins/discourse_math/math_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart';

void main() {
  const settings = MathSettings(enabled: true, asciiMath: true);
  test('only owned cooked markers are recognized', () {
    expect(
      readMathElement(
        parseFragment('<span class="math">x&lt;y</span>').children.single,
      )?.source,
      'x<y',
    );
    expect(
      readMathElement(
        parseFragment('<div class="asciimath">x</div>').children.single,
      ),
      isNull,
    );
    expect(
      readMathElement(
        parseFragment('<code class="math">x</code>').children.single,
      ),
      isNull,
    );
  });
  test('inline boundaries match upstream and protect Markdown', () {
    for (final raw in [
      r'$x$',
      r'。$x$،',
      r'\(x\)',
      r'%sqrt(x)%',
      r'$a<b>c$',
      r'$\text{`x`}$',
    ]) {
      expect(scanMath(raw, settings), hasLength(1), reason: raw);
    }
    for (final raw in [
      r'a$x$',
      r'$x$a',
      r'😀$x$',
      r'☃$x$',
      r'$x$😀',
      r'∑$x$',
      r'`$x$`',
      r'    $x$',
      r'    $$x$$',
      '<div>\n\$x\$\n</div>',
      r'\$x$',
      r'[a](https://x/$y$)',
      r'<span title="$x$">text</span>',
    ]) {
      expect(scanMath(raw, settings), isEmpty, reason: raw);
    }
  });
  test('display source and notation survive editing including CRLF', () {
    final occurrence = scanMath(
      'Before\r\n\\[\r\nx+1\r\n\\]\r\nAfter',
      settings,
    ).single;
    expect(occurrence.expression.display, isTrue);
    expect(occurrence.replace('y+2'), '\\[\r\ny+2\r\n\\]');
    expect(occurrence.replace('y\r\n+2'), '\\[\r\ny\r\n+2\r\n\\]');
    expect(
      scanMath(r'$$x$$', settings).single.replace('x\ny'),
      '\$\$\nx\ny\n\$\$',
    );
    expect(scanMath('\$\$\nx+1', settings).single.expression.source, 'x+1');
    final ascii = scanMath('%sqrt(x)%', settings).single;
    expect(ascii.expression.input, DMathInput.ascii);
    expect(ascii.replace('sqrt(y)'), '%sqrt(y)%');
  });
  test('settings gate syntax and unknown engine keeps readable source', () {
    expect(scanMath(r'$x$', const MathSettings()), isEmpty);
    expect(
      scanMath(
        '%x%',
        const MathSettings(enabled: true, provider: 'katex', asciiMath: true),
      ),
      isEmpty,
    );
    expect(
      const MathSettings(enabled: true, provider: 'future').configuration,
      isNull,
    );
    expect(
      const MathSettings(enabled: true, output: 'future').configuration,
      isNull,
    );
  });
  test(
    'settings default, malformed, unknown, and persisted values are safe',
    () {
      expect(MathSettings.fromWire({}), const MathSettings());
      for (final value in [42, false, <Object?>[], <String, Object?>{}]) {
        expect(
          MathSettings.fromWire({
            'discourse_math_enabled': true,
            'discourse_math_provider': value,
          }).configuration,
          isNull,
        );
        expect(
          const MathSettingsCodec().decode({
            'discourse_math_enabled': true,
            'discourse_math_mathjax_output': value,
          })?.configuration,
          isNull,
        );
      }
      expect(const MathSettingsCodec().decode(settings.toWire()), settings);
    },
  );
}
