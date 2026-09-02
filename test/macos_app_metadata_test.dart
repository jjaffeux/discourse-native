import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS build profiles ship the Discourse application name', () {
    const mainMenus = [
      'macos/Runner/Base.lproj/MainMenu.xib',
      'profiles/full/macos/Runner/Base.lproj/MainMenu.xib',
    ];

    for (final path in mainMenus) {
      final mainMenu = File(path).readAsStringSync();

      expect(
        mainMenu,
        isNot(contains('APP_NAME')),
        reason: '$path must not ship Flutter\'s unsubstituted template token.',
      );
      expect(mainMenu, contains('<menuItem title="Discourse"'));
      expect(mainMenu, contains('<menuItem title="About Discourse"'));
      expect(mainMenu, contains('<menuItem title="Hide Discourse"'));
      expect(mainMenu, contains('<menuItem title="Quit Discourse"'));
      expect(mainMenu, contains('<window title="Discourse"'));
    }
  });

  group('macOS About build information', () {
    final script = File('tool/write_macos_build_info.sh').absolute.path;
    late Directory temporary;
    late Directory repository;
    late Directory resources;

    Future<String> git(List<String> arguments) =>
        _run('git', ['-C', repository.path, ...arguments]);

    Future<void> commit() async {
      await git(['add', '.']);
      await git([
        '-c',
        'user.name=Build metadata test',
        '-c',
        'user.email=build@example.invalid',
        '-c',
        'commit.gpgsign=false',
        'commit',
        '-m',
        'Test build',
      ]);
    }

    Future<String> stamp({
      String? source,
      String configuration = 'Debug',
    }) async {
      await _run('sh', [
        script,
        source ?? repository.path,
        resources.path,
        configuration,
      ]);
      return File('${resources.path}/Credits.rtf').readAsString();
    }

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('macos build info ');
      repository = await Directory('${temporary.path}/source').create();
      resources = Directory(
        '${temporary.path}/Discourse.app/Contents/Resources',
      );
      await git(['init']);
      await File('${repository.path}/app.txt').writeAsString('first build');
      await commit();
    });

    tearDown(() => temporary.delete(recursive: true));

    test(
      'stamps the source commit, configuration, and UTC build time',
      () async {
        final revision = await git(['rev-parse', '--short=12', 'HEAD']);
        final before = DateTime.now().toUtc().subtract(
          const Duration(seconds: 1),
        );

        final credits = await stamp(configuration: 'Release');

        expect(credits, contains('Release build'));
        expect(credits, contains('Commit: $revision\\line'));
        final timestamp = RegExp(
          r'Built: (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) UTC',
        ).firstMatch(credits);
        expect(timestamp, isNotNull);
        final builtAt = DateTime.parse('${timestamp!.group(1)}Z');
        expect(builtAt.isBefore(before), isFalse);
        expect(builtAt.isAfter(DateTime.now().toUtc()), isFalse);
      },
    );

    test(
      'refreshes local modifications and commits on the next build',
      () async {
        final original = await stamp();
        await File('${repository.path}/app.txt').writeAsString('next build');

        expect(await stamp(), contains('(modified)'));
        await git(['add', '.']);
        expect(await stamp(), contains('(modified)'));

        await commit();
        final rebuilt = await stamp();
        final revision = await git(['rev-parse', '--short=12', 'HEAD']);
        expect(rebuilt, contains('Commit: $revision\\line'));
        expect(original, isNot(contains(revision)));
        expect(rebuilt, isNot(contains('(modified)')));
      },
    );

    test(
      'resolves the commit from a compatibility profile in a worktree',
      () async {
        final worktree = '${temporary.path}/linked worktree';
        await git(['worktree', 'add', '--detach', worktree, 'HEAD']);
        final profile = await Directory(
          '$worktree/profiles/full',
        ).create(recursive: true);
        final revision = await git(['rev-parse', '--short=12', 'HEAD']);

        expect(
          await stamp(source: profile.path),
          contains('Commit: $revision\\line'),
        );
      },
    );

    test(
      'builds without Git metadata and escapes RTF configuration names',
      () async {
        final archive = await Directory('${temporary.path}/archive').create();

        final credits = await stamp(
          source: archive.path,
          configuration: r'Debug {local}\test',
        );

        expect(credits, contains('Commit: Unavailable'));
        expect(credits, contains(r'Debug \{local\}\\test build'));
      },
    );
  }, skip: Platform.isWindows ? 'requires POSIX build tools' : false);
}

Future<String> _run(String command, List<String> arguments) async {
  final result = await Process.run(command, arguments);
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  return (result.stdout as String).trim();
}
