import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the desktop installer quotes an arbitrary bundle path',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'discourse-desktop-installer-',
      );
      addTearDown(() => root.delete(recursive: true));

      final bundle = Directory('${root.path}/Discourse Native &\$`"\\| (100%)')
        ..createSync(recursive: true);
      final desktopAssets = Directory('${bundle.path}/data/desktop')
        ..createSync(recursive: true);
      final iconTheme = Directory('${desktopAssets.path}/icons/hicolor')
        ..createSync(recursive: true);
      await File(
        'linux/packaging/org.discourse.native.desktop',
      ).copy('${desktopAssets.path}/org.discourse.native.desktop');
      final installer = await File(
        'linux/packaging/install-desktop-entry.sh',
      ).copy('${bundle.path}/install-desktop-entry.sh');
      await File(
        '${iconTheme.path}/index.theme',
      ).writeAsString('[Icon Theme]\n');
      final binary = File('${bundle.path}/discourse_native');
      await binary.writeAsString('#!/bin/sh\n');
      final chmod = await Process.run('chmod', ['755', binary.path]);
      expect(chmod.exitCode, 0, reason: '${chmod.stderr}');

      final dataHome = Directory('${root.path}/installed data')
        ..createSync(recursive: true);
      final result = await Process.run(
        '/bin/sh',
        [installer.path],
        environment: {...Platform.environment, 'XDG_DATA_HOME': dataHome.path},
      );

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final desktopFile = File(
        '${dataHome.path}/applications/org.discourse.native.desktop',
      );
      final exec = (await desktopFile.readAsLines()).singleWhere(
        (line) => line.startsWith('Exec='),
      );
      expect(exec, 'Exec="${_desktopExec(binary.path)}"');
      expect(
        _parseSingleDesktopExec(exec.substring('Exec='.length)),
        binary.path,
      );
      try {
        final validation = await Process.run('desktop-file-validate', [
          desktopFile.path,
        ]);
        expect(validation.exitCode, 0, reason: '${validation.stderr}');
      } on ProcessException {
        // desktop-file-utils is present in the Linux packaging job, but it is
        // not a Flutter development dependency on Apple hosts.
      }
      expect(
        File('${dataHome.path}/icons/hicolor/index.theme').existsSync(),
        isTrue,
      );
    },
    skip: Platform.isWindows
        ? 'Requires a POSIX shell and Linux desktop-entry filesystem layout.'
        : false,
  );
}

String _desktopExec(String path) => path
    .replaceAll('\\', '\\\\\\\\')
    .replaceAll('"', r'\\"')
    .replaceAll('`', '\\\\`')
    .replaceAll(r'$', r'\\$')
    .replaceAll('%', '%%');

String _parseSingleDesktopExec(String encoded) {
  final command = _unescapeDesktopString(encoded);
  if (command.length < 2 ||
      !command.startsWith('"') ||
      !command.endsWith('"')) {
    throw const FormatException('Expected one quoted executable.');
  }

  final executable = StringBuffer();
  for (var index = 1; index < command.length - 1; index++) {
    final character = command[index];
    if (character == '%' && command[index + 1] == '%') {
      executable.write('%');
      index++;
      continue;
    }
    if (character != '\\') {
      executable.write(character);
      continue;
    }
    index++;
    if (index >= command.length - 1 ||
        !const {'`', '"', '\\', r'$'}.contains(command[index])) {
      throw const FormatException('Invalid quoted Exec escape.');
    }
    executable.write(command[index]);
  }
  return executable.toString();
}

String _unescapeDesktopString(String encoded) {
  final decoded = StringBuffer();
  for (var index = 0; index < encoded.length; index++) {
    final character = encoded[index];
    if (character != '\\') {
      decoded.write(character);
      continue;
    }
    index++;
    if (index >= encoded.length) {
      throw const FormatException('Incomplete desktop-entry escape.');
    }
    decoded.write(switch (encoded[index]) {
      's' => ' ',
      'n' => '\n',
      't' => '\t',
      'r' => '\r',
      '\\' => '\\',
      _ => throw const FormatException('Invalid desktop-entry escape.'),
    });
  }
  return decoded.toString();
}
