import 'package:discourse_native/discourse_ui.dart';
import '../styleguide_example.dart';

final mathExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description:
      'Offline TeX and ASCII math with source fallback and Native actions.',
  notes:
      'Uses MathJax 4.1.0 (HTML or SVG) and KaTeX 0.16.27, with bundled fonts, chemistry, and accessibility resources. Context actions expose available MathML, SVG, speech and braille. Native selection does not span the WebView and surrounding Flutter text.',
  examples: [
    StyleguideExample(
      title: 'Inline',
      description: 'Inline TeX retains a measured text baseline.',
      states: const ['Light', 'Dark', 'Narrow'],
      code:
          r'DMath(expression: DMathExpression(r"\frac{a}{b}"), configuration: DMathJax())',
      builder: (_) => const DMath(
        expression: DMathExpression(r'\frac{a}{b}'),
        configuration: DMathJax(),
      ),
    ),
    StyleguideExample(
      title: 'Display',
      description: 'Display equations scroll horizontally when needed.',
      states: const ['Light', 'Dark', 'Narrow'],
      code:
          r'DMath(expression: DMathExpression(r"E=mc^2", display: true), configuration: DMathJax())',
      builder: (_) => const DMath(
        expression: DMathExpression(
          r'\int_0^\infty e^{-x^2}\,dx=\frac{\sqrt\pi}{2}',
          display: true,
        ),
        configuration: DMathJax(),
      ),
    ),
    StyleguideExample(
      title: 'Chemistry',
      description: 'KaTeX includes the mhchem extension.',
      states: const ['Light', 'Dark'],
      code:
          r'DMath(expression: DMathExpression(r"\ce{H2O}"), configuration: DMathKatex())',
      builder: (_) => const DMath(
        expression: DMathExpression(r'\ce{CO2 + C -> 2 CO}', display: true),
        configuration: DMathKatex(),
      ),
    ),
    StyleguideExample(
      title: 'ASCII',
      description: 'MathJax accepts its distinct ASCII input language.',
      states: const ['Light', 'Dark'],
      code:
          'DMath(expression: DMathExpression("sqrt(x^2+1)", input: DMathInput.ascii), configuration: DMathJax())',
      builder: (_) => const DMath(
        expression: DMathExpression('sqrt(x^2+1)', input: DMathInput.ascii),
        configuration: DMathJax(),
      ),
    ),
  ],
);
