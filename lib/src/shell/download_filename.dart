String downloadFilename({
  required String? title,
  required String url,
  required String fallback,
}) {
  final uri = Uri.tryParse(url);
  final urlName = uri?.pathSegments.lastOrNull;
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
  final stem = filename.split('.').first.toUpperCase();
  if (_windowsDeviceNames.contains(stem)) filename = '_$filename';
  return filename;
}

String? _extension(String filename) {
  final match = RegExp(r'\.([A-Za-z0-9]{1,10})$').firstMatch(filename);
  return match?.group(1)?.toLowerCase();
}

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
