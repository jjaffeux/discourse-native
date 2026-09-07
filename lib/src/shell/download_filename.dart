String downloadFilename({
  required String? title,
  required String url,
  required String fallback,
}) {
  final urlName = _urlFilename(url);
  final trimmedTitle = title?.trim();
  // HTML parsing has already decoded the title, and Uri.pathSegments has
  // already decoded the URL component. Decoding either again turns a valid
  // literal percent sign into an illegal percent escape.
  var filename = switch (trimmedTitle) {
    final title? when title.isNotEmpty => title,
    _ => urlName ?? fallback,
  };
  filename = filename
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (filename.isEmpty || filename == '.' || filename == '..') {
    filename = fallback;
  }

  final extension = _extension(filename);
  if (extension == null) {
    final urlExtension = _extension(urlName ?? '');
    if (urlExtension != null) filename = '$filename.$urlExtension';
  }

  // Windows refuses these device names even when they have an extension.
  final firstDot = filename.indexOf('.');
  final stem = (firstDot < 0 ? filename : filename.substring(0, firstDot))
      .toUpperCase();
  if (_windowsDeviceNames.contains(stem)) filename = '_$filename';
  return _boundedFilename(filename, fallback);
}

String? _urlFilename(String url) {
  try {
    return Uri.tryParse(url)?.pathSegments.lastOrNull;
  } on FormatException {
    // URI syntax can be valid while a percent-encoded filename is not UTF-8.
    // The upload title and fallback remain usable in that case.
    return null;
  }
}

String _boundedFilename(String filename, String fallback) {
  // Keep a byte budget for native filesystems, with room for a save dialog's
  // collision suffix. Count Unicode scalars so truncation cannot split UTF-16
  // surrogate pairs or UTF-8 byte sequences, and reserve the full extension.
  const maximumBytes = 240;
  final match = _extensionPattern.firstMatch(filename);
  final suffix = match == null ? '' : filename.substring(match.start);
  final stem = match == null ? filename : filename.substring(0, match.start);
  final buffer = StringBuffer();
  var bytes = suffix.length;
  for (final rune in stem.runes) {
    final size = switch (rune) {
      < 0x80 => 1,
      < 0x800 => 2,
      < 0x10000 => 3,
      _ => 4,
    };
    if (bytes + size > maximumBytes) {
      final bounded = buffer.toString().replaceAll(RegExp(r'[. ]+$'), '');
      return '${bounded.isEmpty ? fallback : bounded}$suffix';
    }
    buffer.writeCharCode(rune);
    bytes += size;
  }
  return '$buffer$suffix';
}

String? _extension(String filename) {
  final match = _extensionPattern.firstMatch(filename);
  return match?.group(1)?.toLowerCase();
}

final _extensionPattern = RegExp(r'\.([A-Za-z0-9]{1,10})$');

const _windowsDeviceNames = {
  'CON',
  'PRN',
  'AUX',
  'NUL',
  'COM1',
  'COM2',
  'COM3',
  'COM4',
  'COM5',
  'COM6',
  'COM7',
  'COM8',
  'COM9',
  'LPT1',
  'LPT2',
  'LPT3',
  'LPT4',
  'LPT5',
  'LPT6',
  'LPT7',
  'LPT8',
  'LPT9',
};
