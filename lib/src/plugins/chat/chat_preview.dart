import 'package:flutter/widgets.dart';

import '../../diagnostics/diagnostics_controller.dart';
import '../../shell/markdown_highlight.dart';
import 'chat_preview_contract.dart';

export 'chat_preview_contract.dart';

/// Provisional only; server-cooked content always replaces this document.
final class ChatPreviewEngine {
  ChatPreviewEngine({
    Iterable<ChatPreviewPluginAdapter> plugins = const [],
    this.reporter = const PluginDiagnosticsReporter.noop(),
    this.maxSourceLength = 20000,
    this.maxPluginClaims = 128,
    this.maxDocumentNodes = 4096,
  }) : _plugins = List.unmodifiable(plugins);

  final List<ChatPreviewPluginAdapter> _plugins;
  final PluginDiagnosticsReporter reporter;
  final int maxSourceLength;
  final int maxPluginClaims;
  final int maxDocumentNodes;

  Widget? buildPreviewNode(BuildContext context, PluginPreviewNode node) {
    ChatPreviewContribution? owner;
    for (final plugin in _plugins.whereType<ChatPreviewContribution>()) {
      if (plugin.previewFeatureId != node.featureId) continue;
      if (owner != null) return null;
      owner = plugin;
    }
    if (owner == null) return null;
    try {
      return owner.buildPreviewNode(context, node);
    } catch (error, stackTrace) {
      reporter.reportError(
        error,
        stackTrace,
        operation: 'chat.previewPlugin.render',
        source: 'chat',
        severity: DiagnosticSeverity.warning,
        handled: true,
        degraded: true,
      );
      return null;
    }
  }

  ChatPreviewEngine withPlugins(Iterable<ChatPreviewPluginAdapter> plugins) =>
      ChatPreviewEngine(
        plugins: plugins,
        reporter: reporter,
        maxSourceLength: maxSourceLength,
        maxPluginClaims: maxPluginClaims,
        maxDocumentNodes: maxDocumentNodes,
      );

  ChatPreviewResult project(ChatPreviewRequest request) {
    try {
      return _project(request);
    } catch (_) {
      return SourceFallback(
        request.raw,
        ChatPreviewFallbackReason.internalFailure,
      );
    }
  }

  ChatPreviewResult _project(ChatPreviewRequest request) {
    final source = request.raw;
    if (source.length > maxSourceLength) {
      return _fallback(request, ChatPreviewFallbackReason.resourceLimit);
    }

    final seed = request.trustedSeed;
    if (seed != null) {
      return _projectTrustedSeed(request, seed);
    }

    final claims = <ChatPreviewClaim>[];
    final featureIds = <String>{};
    for (final plugin in _plugins) {
      final featureId = plugin.previewFeatureId.trim();
      if (featureId.isEmpty || !featureIds.add(featureId)) {
        return _fallback(request, ChatPreviewFallbackReason.duplicatePluginId);
      }

      final ChatPreviewInspection inspection;
      try {
        inspection = plugin.inspect(request);
      } catch (_) {
        return _fallback(request, ChatPreviewFallbackReason.pluginFailure);
      }
      if (inspection.blockers.isNotEmpty) {
        return _fallback(request, ChatPreviewFallbackReason.pluginBlocked);
      }
      if (claims.length + inspection.claims.length > maxPluginClaims) {
        return _fallback(request, ChatPreviewFallbackReason.resourceLimit);
      }
      for (final claim in inspection.claims) {
        if (claim.node.featureId != featureId ||
            claim.node.range != claim.range ||
            !claim.range.isValidFor(source) ||
            claim.range.isEmpty ||
            claim.node.fallbackText !=
                source.substring(claim.range.start, claim.range.end)) {
          return _fallback(
            request,
            ChatPreviewFallbackReason.invalidPluginClaim,
          );
        }
        claims.add(claim);
      }
    }

    claims.sort((a, b) => a.range.start.compareTo(b.range.start));
    for (var index = 1; index < claims.length; index++) {
      if (claims[index - 1].range.overlaps(claims[index].range)) {
        return _fallback(
          request,
          ChatPreviewFallbackReason.overlappingPluginClaims,
        );
      }
    }

    final claimedSource = _replaceClaims(source, claims);
    final grammarSource = _normalizeChatDialect(claimedSource);
    final runs = scanMarkdown(grammarSource);
    if (_hasUnsupportedScannerSyntax(runs)) {
      return _fallback(request, ChatPreviewFallbackReason.unsupportedSyntax);
    }

    final fences = _closedFences(grammarSource);
    if (fences == null) {
      return _fallback(request, ChatPreviewFallbackReason.ambiguousSyntax);
    }

    final codeRanges = CodeRanges.of(runs);
    if (_hasUnsupportedSourceSyntax(grammarSource, codeRanges, fences)) {
      return _fallback(request, ChatPreviewFallbackReason.unsupportedSyntax);
    }

    final nodes = _buildDocument(source, runs, claims, fences);
    if (nodes.length > maxDocumentNodes) {
      return _fallback(request, ChatPreviewFallbackReason.resourceLimit);
    }
    if (!_fullyAccountsFor(source.length, nodes)) {
      return _fallback(request, ChatPreviewFallbackReason.internalFailure);
    }
    return ProjectedPreview(PreviewDocument(source, nodes));
  }

  ChatPreviewResult _projectTrustedSeed(
    ChatPreviewRequest request,
    TrustedPreviewSeed seed,
  ) {
    if (seed is! TrustedGifPreviewSeed ||
        !_validImageUri(seed.url) ||
        seed.width <= 0 ||
        seed.height <= 0 ||
        seed.width > 10000 ||
        seed.height > 10000 ||
        seed.title.trim().isEmpty) {
      return _fallback(request, ChatPreviewFallbackReason.invalidTrustedSeed);
    }
    final node = ChatPreviewImage(
      range: SourceRange(0, request.raw.length),
      url: seed.url,
      title: seed.title,
      width: seed.width,
      height: seed.height,
      fallbackText: request.raw,
    );
    return ProjectedPreview(PreviewDocument(request.raw, [node]));
  }

  SourceFallback _fallback(
    ChatPreviewRequest request,
    ChatPreviewFallbackReason reason,
  ) => SourceFallback(request.raw, reason);
}

const int _unsupportedScannerMask =
    Md.heading |
    Md.quote |
    Md.linkText |
    Md.linkUrl |
    Md.mention |
    Md.emoji |
    Md.htmlTag |
    Md.hashtag;

bool _hasUnsupportedScannerSyntax(List<MarkdownRun> runs) =>
    runs.any((run) => run.mask & _unsupportedScannerMask != 0);

String _replaceClaims(String source, List<ChatPreviewClaim> claims) {
  if (claims.isEmpty) return source;
  final units = List<int>.of(source.codeUnits);
  for (final claim in claims) {
    for (var offset = claim.range.start; offset < claim.range.end; offset++) {
      if (units[offset] != 0x0A && units[offset] != 0x0D) units[offset] = 0x78;
    }
  }
  return String.fromCharCodes(units);
}

String _normalizeChatDialect(String source) {
  final codeRanges = CodeRanges.of(scanMarkdown(source));
  final tripled = _replaceUnderscorePair(source, '___', codeRanges);
  return _replaceUnderscorePair(tripled, '__', codeRanges);
}

/// Rewrites double underscores character-for-character so offsets remain
/// stable. [markdownPairs] avoids rescanning long unpaired dunder-heavy input.
String _replaceUnderscorePair(
  String source,
  String delimiter,
  CodeRanges excluded,
) {
  final width = delimiter.length;
  final units = List<int>.of(source.codeUnits);
  for (final block in markdownBlocks(source)) {
    for (final (open, close) in markdownPairs(
      block.text,
      delimiter,
      wordBounded: true,
    )) {
      final start = block.offset + open;
      final end = block.offset + close;
      if (excluded.overlaps(start, end)) continue;
      for (var index = 0; index < width; index++) {
        units[start + index] = 0x2A;
        units[end - width + index] = 0x2A;
      }
    }
  }
  return String.fromCharCodes(units);
}

bool _hasUnsupportedSourceSyntax(
  String source,
  CodeRanges codeRanges,
  List<_FenceBlock> fences,
) {
  // Detect indented CommonMark code before masking scanner code ranges, while
  // hiding fenced bodies whose indentation is literal.
  final outsideFences = List<int>.of(source.codeUnits);
  for (final fence in fences) {
    _maskRange(outsideFences, fence.range);
  }
  if (_indentedCode.hasMatch(String.fromCharCodes(outsideFences))) return true;

  final visible = List<int>.of(source.codeUnits);
  for (final (start, end) in codeRanges.ranges) {
    _mask(visible, start, end);
  }
  final outsideCode = String.fromCharCodes(visible);

  return _heading.hasMatch(outsideCode) ||
      _quote.hasMatch(outsideCode) ||
      _list.hasMatch(outsideCode) ||
      _tableDelimiter.hasMatch(outsideCode) ||
      _html.hasMatch(outsideCode) ||
      _bbCode.hasMatch(outsideCode) ||
      _templateDirective.hasMatch(outsideCode) ||
      _markdownEscape.hasMatch(outsideCode) ||
      _slashCommand.hasMatch(outsideCode) ||
      _unknownEmoji.hasMatch(outsideCode) ||
      _htmlEntity.hasMatch(outsideCode) ||
      _typographicReplacement.hasMatch(outsideCode) ||
      _emailLink.hasMatch(outsideCode);
}

void _maskRange(List<int> units, SourceRange range) =>
    _mask(units, range.start, range.end);

void _mask(List<int> units, int start, int end) {
  for (var offset = start; offset < end; offset++) {
    if (units[offset] != 0x0A && units[offset] != 0x0D) {
      units[offset] = 0x20;
    }
  }
}

final RegExp _heading = RegExp(r'^\s{0,3}#{1,6}(?:\s+|$)', multiLine: true);
final RegExp _quote = RegExp(r'^\s{0,3}>', multiLine: true);
final RegExp _list = RegExp(r'^\s{0,3}(?:[-+*]|\d+[.)])\s+', multiLine: true);
final RegExp _tableDelimiter = RegExp(
  r'^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$',
  multiLine: true,
);
final RegExp _html = RegExp(r'<!--|</?[a-zA-Z][^>]*>', caseSensitive: false);
final RegExp _bbCode = RegExp(
  r'\[/?[a-zA-Z][a-zA-Z0-9_-]*(?:\s+[^\]]*|=[^\]]*)?\]',
);
final RegExp _templateDirective = RegExp(r'\{\{[^\r\n{}]+\}\}');
final RegExp _markdownEscape = RegExp(r'\\[*_~`\[\]#>\\]');
final RegExp _slashCommand = RegExp(
  r'^\s*/[a-zA-Z][a-zA-Z0-9_-]*(?:\s|$)',
  multiLine: true,
);
final RegExp _unknownEmoji = RegExp(r':[A-Z][A-Za-z0-9_+-]*:');
final RegExp _indentedCode = RegExp(r'^(?: {4,}| {0,3}\t)\S', multiLine: true);
final RegExp _htmlEntity = RegExp(
  r'&(?:#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z][a-zA-Z0-9]+);',
);
final RegExp _typographicReplacement = RegExp(
  r'\+-|\.{3,}|[?!]{4,}|,{2,}|--|->|<-|\((?:tm|pa)\)',
  caseSensitive: false,
);
final RegExp _emailLink = RegExp(
  r'\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b',
);

@immutable
final class _FenceBlock {
  const _FenceBlock({
    required this.range,
    required this.bodyRange,
    required this.language,
  });

  final SourceRange range;
  final SourceRange bodyRange;
  final String? language;
}

List<_FenceBlock>? _closedFences(String source) {
  final lines = _sourceLines(source);
  final blocks = <_FenceBlock>[];
  _OpenFence? open;
  for (final line in lines) {
    final match = _fenceLine.firstMatch(line.text);
    if (match == null) continue;
    final delimiter = match.group(1)!;
    if (open == null) {
      open = _OpenFence(line, delimiter, match.group(2)!.trim());
      continue;
    }
    if (match.group(2)!.trim().isEmpty &&
        delimiter.codeUnitAt(0) == open.delimiter.codeUnitAt(0) &&
        delimiter.length >= open.delimiter.length) {
      final bodyStart = open.line.endWithNewline;
      final bodyEnd = line.start;
      blocks.add(
        _FenceBlock(
          // The closing-fence newline belongs to the block, unlike cooked <pre>.
          range: SourceRange(open.line.start, line.endWithNewline),
          bodyRange: SourceRange(bodyStart, bodyEnd),
          language: open.info.isEmpty ? null : open.info,
        ),
      );
      open = null;
    }
  }
  return open == null ? blocks : null;
}

final RegExp _fenceLine = RegExp(r'^\s{0,3}(`{3,}|~{3,})\s*(.*)$');

@immutable
final class _OpenFence {
  const _OpenFence(this.line, this.delimiter, this.info);

  final _SourceLine line;
  final String delimiter;
  final String info;
}

@immutable
final class _SourceLine {
  const _SourceLine(this.start, this.end, this.endWithNewline, this.text);

  final int start;
  final int end;
  final int endWithNewline;
  final String text;
}

List<_SourceLine> _sourceLines(String source) {
  final lines = <_SourceLine>[];
  var start = 0;
  while (start < source.length) {
    final newline = source.indexOf('\n', start);
    final end = newline == -1 ? source.length : newline;
    lines.add(
      _SourceLine(
        start,
        end,
        newline == -1 ? end : end + 1,
        source.substring(start, end),
      ),
    );
    if (newline == -1) break;
    start = newline + 1;
  }
  return lines;
}

List<ChatPreviewNode> _buildDocument(
  String source,
  List<MarkdownRun> runs,
  List<ChatPreviewClaim> claims,
  List<_FenceBlock> fences,
) {
  final nodes = <ChatPreviewNode>[];
  var offset = 0;
  var runIndex = 0;
  var claimIndex = 0;
  var fenceIndex = 0;

  while (offset < source.length) {
    while (runIndex < runs.length && runs[runIndex].end <= offset) {
      runIndex++;
    }
    final run = runs[runIndex];

    if (fenceIndex < fences.length &&
        fences[fenceIndex].range.start == offset) {
      final fence = fences[fenceIndex++];
      nodes.add(
        ChatPreviewCodeBlock(
          range: fence.range,
          bodyRange: fence.bodyRange,
          code: source.substring(fence.bodyRange.start, fence.bodyRange.end),
          language: fence.language,
        ),
      );
      offset = fence.range.end;
      continue;
    }

    if (claimIndex < claims.length &&
        claims[claimIndex].range.start == offset) {
      final claim = claims[claimIndex++];
      nodes.add(claim.node.withStyles(_stylesFor(run.mask)));
      offset = claim.range.end;
      continue;
    }

    var end = run.end;
    if (fenceIndex < fences.length && fences[fenceIndex].range.start > offset) {
      end = end.clamp(offset, fences[fenceIndex].range.start);
    }
    if (claimIndex < claims.length && claims[claimIndex].range.start > offset) {
      end = end.clamp(offset, claims[claimIndex].range.start);
    }
    final newline = source.indexOf('\n', offset);
    if (newline >= offset && newline < end) {
      end = newline > offset && source[newline - 1] == '\r'
          ? newline - 1
          : newline;
    }

    if (end == offset &&
        (source[offset] == '\n' ||
            (source[offset] == '\r' &&
                offset + 1 < source.length &&
                source[offset + 1] == '\n'))) {
      final lineBreakEnd = source[offset] == '\r' ? offset + 2 : offset + 1;
      nodes.add(ChatPreviewLineBreak(range: SourceRange(offset, lineBreakEnd)));
      offset = lineBreakEnd;
      continue;
    }

    final range = SourceRange(offset, end);
    if (run.has(Md.marker)) {
      nodes.add(
        ChatPreviewSyntax(range: range, source: source.substring(offset, end)),
      );
    } else {
      nodes.add(
        ChatPreviewText(
          range: range,
          text: source.substring(offset, end),
          styles: _stylesFor(run.mask),
        ),
      );
    }
    offset = end;
  }
  return List.unmodifiable(nodes);
}

Set<ChatPreviewTextStyle> _stylesFor(int mask) => {
  if (mask & Md.bold != 0) ChatPreviewTextStyle.bold,
  if (mask & Md.italic != 0) ChatPreviewTextStyle.italic,
  if (mask & Md.strikethrough != 0) ChatPreviewTextStyle.strikethrough,
  if (mask & Md.code != 0) ChatPreviewTextStyle.code,
};

bool _fullyAccountsFor(int length, List<ChatPreviewNode> nodes) {
  if (length == 0) return nodes.isEmpty;
  var offset = 0;
  for (final node in nodes) {
    if (node.range.start != offset || node.range.end <= offset) return false;
    offset = node.range.end;
  }
  return offset == length;
}

bool _validImageUri(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http') &&
    uri.host.isNotEmpty &&
    !uri.hasFragment;
