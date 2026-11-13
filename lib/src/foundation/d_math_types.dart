import 'package:flutter/foundation.dart' show immutable;

enum DMathInput { tex, ascii }

enum DMathJaxOutput { html, svg }

sealed class DMathConfiguration {
  const DMathConfiguration();
  Map<String, Object?> toMessage();
}

final class DMathJax extends DMathConfiguration {
  const DMathJax({
    this.output = DMathJaxOutput.html,
    this.menu = true,
    this.zoom = false,
    this.accessibility = false,
  });
  final DMathJaxOutput output;
  final bool menu, zoom, accessibility;
  @override
  Map<String, Object?> toMessage() => {
    'engine': 'mathjax',
    'output': output.name,
    'accessibility': accessibility,
    'menu': menu,
    'zoom': zoom,
  };
  @override
  bool operator ==(Object other) =>
      other is DMathJax &&
      output == other.output &&
      menu == other.menu &&
      zoom == other.zoom &&
      accessibility == other.accessibility;
  @override
  int get hashCode => Object.hash(output, menu, zoom, accessibility);
}

final class DMathKatex extends DMathConfiguration {
  const DMathKatex();
  @override
  Map<String, Object?> toMessage() => {'engine': 'katex'};
  @override
  bool operator ==(Object other) => other is DMathKatex;
  @override
  int get hashCode => 0x4b61546558;
}

@immutable
final class DMathExpression {
  const DMathExpression(
    this.source, {
    this.input = DMathInput.tex,
    this.display = false,
  });
  final String source;
  final DMathInput input;
  final bool display;
  Map<String, Object?> toMessage() => {
    'source': source,
    'input': input.name,
    'display': display,
  };
}
