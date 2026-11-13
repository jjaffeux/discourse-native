import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late File file;
  late _CountingPreferences preferences;
  late _StorageWork work;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'discourse-native-draft-autosave-test-',
    );
    file = File('${directory.path}/drafts/drafts-v1.json');
    final previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    preferences = _CountingPreferences();
    SharedPreferencesStorePlatform.instance = preferences;
    work = _StorageWork(file.parent.path);
    addTearDown(() async {
      SharedPreferencesStorePlatform.instance = previous;
      SharedPreferences.resetStatic();
      if (await directory.exists()) await directory.delete(recursive: true);
    });
  });

  test('typing into a small draft spawns no codec isolate and makes no no-op '
      'storage call', () async {
    const saves = 10;
    await work.run(() async {
      const user = DiscourseUser(id: 7, username: 'sam', canCreateTopic: true);
      final api = FakeDiscourseApi(
        user: user,
        feeds: const {'/latest.json': []},
        creatableFeedPaths: const {'/latest.json'},
      );
      final shell = ShellController(
        forumTabsEnabled: false,
        instanceStore: FakeInstanceStore([
          instance('meta.discourse.org').copyWith(user: user),
        ]),
        api: api,
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'key',
        drafts: DraftStore(
          persistence: ApplicationSupportDraftPersistence(file: () => file),
        ),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(shell.dispose);
      await shell.load();
      await shell.openNewTopicFromSidebar();
      final composer = shell.visibleComposer!;
      composer.title.text = 'A topic title long enough';
      await composer.flushDraft();
      await composer.finishDraftSaves();

      work.reset();
      preferences.removals = 0;
      api.draftsSaved.clear();

      for (var save = 1; save <= saves; save++) {
        composer.text.value = TextEditingValue(
          text: 'Body revision $save ' * 20,
        );
        await composer.flushDraft();
        await composer.finishDraftSaves();
      }

      expect(api.draftsSaved, hasLength(saves));
      expect(api.draftsSaved.last['data'], contains('Body revision $saves'));
      final document = jsonDecode(await file.readAsString()) as Map;
      expect(document['values'], isEmpty);
    });

    // ignore: avoid_print
    print('PERF_PROOF draft-autosave isolate_spawns=${work.isolateSpawns}');
    // ignore: avoid_print
    print('PERF_PROOF draft-autosave prefs_removes=${preferences.removals}');
    // ignore: avoid_print
    print(
      'PERF_PROOF draft-autosave directory_listings='
      '${work.directoryListings}',
    );
    // ignore: avoid_print
    print('PERF_PROOF draft-autosave fsynced_replaces=${work.replaces}');

    expect(work.isolateSpawns, 0);
    expect(preferences.removals, 0);
    expect(work.directoryListings, 0);
    expect(work.replaces, 2 * saves);
  });

  test('a maximum-length post still leaves the UI isolate', () async {
    const key = 'discourse_native.draft::https://meta.discourse.org::topic_42';
    final drafts = ApplicationSupportDraftPersistence(file: () => file);
    final post = 'x' * 32000;

    await work.run(() async {
      await drafts.write(key, post);
      work.reset();
      await drafts.write(key, '$post!');
    });

    expect(work.isolateSpawns, 2);
    expect((await drafts.read(key)).value, '$post!');
  });

  group('a legacy preference draft', () {
    const site = 'https://meta.discourse.org';
    const key = 'discourse_native.draft::$site::topic_42';

    setUp(() => preferences.setValue('String', 'flutter.$key', 'legacy draft'));

    test('is retired by a write', () async {
      final persistence = ApplicationSupportDraftPersistence(file: () => file);

      await DraftStore(
        persistence: persistence,
      ).write(site, 'topic_42', 'new draft');

      expect(preferences.removals, 1);
      expect(await preferences.getAll(), isNot(contains('flutter.$key')));
      expect((await persistence.read(key)).value, 'new draft');
    });

    test('is retired by a clear', () async {
      final store = DraftStore(
        persistence: ApplicationSupportDraftPersistence(file: () => file),
      );

      expect(await store.clearChecked(site, 'topic_42'), isTrue);

      expect(preferences.removals, 1);
      expect(await preferences.getAll(), isNot(contains('flutter.$key')));
    });
  });
}

/// Counts through a zone and `IOOverrides` because the isolate spawn, the
/// directory listing and the staged file have no production seam: a test must
/// not need one to see that they stopped happening.
final class _StorageWork extends IOOverrides {
  _StorageWork(this._drafts);

  final String _drafts;
  int isolateSpawns = 0;
  int directoryListings = 0;
  int replaces = 0;

  void reset() {
    isolateSpawns = 0;
    directoryListings = 0;
    replaces = 0;
  }

  /// Registering its `await` in the calling zone is the only trace
  /// `Isolate.spawn` leaves there, and it does so once per spawn.
  Future<T> run<T>(Future<T> Function() body) => runZoned(
    () => IOOverrides.runWithIOOverrides(body, this),
    zoneSpecification: ZoneSpecification(
      registerUnaryCallback: <R, A>(self, parent, zone, callback) {
        if (StackTrace.current.toString().contains('Isolate.spawn')) {
          isolateSpawns++;
        }
        return parent.registerUnaryCallback(zone, callback);
      },
    ),
  );

  @override
  File createFile(String path) {
    if (path.endsWith('.private-document.tmp')) replaces++;
    return super.createFile(path);
  }

  @override
  Directory createDirectory(String path) {
    final directory = super.createDirectory(path);
    return path == _drafts ? _CountedDirectory(directory, this) : directory;
  }
}

final class _CountedDirectory extends Fake implements Directory {
  _CountedDirectory(this._directory, this._work);

  final Directory _directory;
  final _StorageWork _work;

  @override
  String get path => _directory.path;

  @override
  Future<Directory> create({bool recursive = false}) async {
    await _directory.create(recursive: recursive);
    return this;
  }

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) {
    _work.directoryListings++;
    return _directory.list(recursive: recursive, followLinks: followLinks);
  }
}

final class _CountingPreferences extends InMemorySharedPreferencesStore {
  _CountingPreferences() : super.empty();

  int removals = 0;

  @override
  Future<bool> remove(String key) {
    removals++;
    return super.remove(key);
  }
}
