import 'dart:async';
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/data/application_cooking.dart';
import 'package:discourse_native/src/plugins/cooking/cooking_module.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_api.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_controller.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_data.dart';
import 'package:flutter/foundation.dart';

const notesSite = 'https://forum.example/community';
const notesOtherSite = 'https://second.example';
Map<String, dynamic> noteWire({
  String id = 'note-1',
  int userId = 7,
  String raw = 'Private **staff** context.',
  bool canDelete = true,
  Object? postId,
  String? postUrl,
  Object? reviewableId,
}) => {
  'id': id,
  'user_id': userId,
  'raw': raw,
  'created_by': {'id': -1, 'username': 'system', 'avatar_template': null},
  'created_at': '2026-10-28T12:30:00Z',
  'can_delete': canDelete,
  'post_id': ?postId,
  'post_url': ?postUrl,
  'reviewable_id': ?reviewableId,
};
Map<String, dynamic> notesPage(List<Map<String, dynamic>> notes) => {
  'extras': {'username': 'mira'},
  'user_notes': notes,
};

final class NotesFixture {
  NotesFixture({
    bool enabled = true,
    bool staff = true,
    int? maximumLength,
    bool failCooking = false,
  }) {
    fresh.staff = staff;
    config = ValueNotifier(
      SiteConfig(
        emojiEnabled: false,
        plugins: PluginData.none.withValue(
          userNotesSettingsKey,
          UserNotesSettings(enabled: enabled, maximumLength: maximumLength),
        ),
      ),
    );
    transport = RecordingPluginTransport(
      responders: {
        'GET /user_notes.json?user_id=7': (_) => notesPage([noteWire()]),
        'POST /user_notes': (request) {
          final body = request.body['user_note']! as Map<String, Object?>;
          return {
            'user_note': noteWire(
              id: 'note-created',
              userId: body['user_id']! as int,
              raw: body['raw']! as String,
              postId: body['post_id'],
              postUrl: body['post_id'] == null
                  ? null
                  : '/community/t/welcome/11/1',
            ),
          };
        },
        'DELETE /user_notes/note-1?user_id=7': (_) => {'success': 'OK'},
      },
    );
    cookingHost = PluginCookingHost(
      request:
          ({
            required String siteUrl,
            required String raw,
            CookingProfile profile = CookingProfile.post,
            CookingContext context = const CookingContext(),
            CookingCachedMetadata? cachedMetadata,
          }) => cooker.request(
            siteUrl: siteUrl,
            accountId: '1',
            raw: raw,
            config: config.value,
            profile: profile,
            context: context,
            cachedMetadata: cachedMetadata,
          ),
      cook: (request) {
        regularCooking++;
        return cooker.cook(request);
      },
      cookTransient: (request, {required abortTrigger}) {
        transientCooking++;
        return failCooking
            ? Future.value(
                CookingResult(
                  html: '<pre>truncated</pre>',
                  failure: CookingFailure.inputLimit,
                ),
              )
            : cooker.cookTransient(request, abortTrigger: abortTrigger);
      },
    );
    controller = UserNotesController(
      api: UserNotesApiClient(transport),
      requests: requests,
      account: fresh,
      site: PluginSiteStateHost(
        currentUserFor: (_) => const DiscourseUser(id: 1, username: 'staff'),
        siteConfigFor: (_) => config.value,
        siteConfigListenableFor: (_) => config,
      ),
      cooking: cookingHost,
    );
  }
  final fresh = NotesFreshAccount();
  final requests = PluginTestRequestHost(
    apiKeys: {notesSite: 'first-key', notesOtherSite: 'second-key'},
  );
  late final RecordingPluginTransport transport;
  late final ValueNotifier<SiteConfig> config;
  final installed = PluginInstaller.install(
    const PluginManifest([cookingModule]),
  );
  late final cooker = ApplicationCooking(plugins: installed);
  late final PluginCookingHost cookingHost;
  late final UserNotesController controller;
  int regularCooking = 0, transientCooking = 0;
  void settings({
    required bool enabled,
    UserNotesPlacement placement = UserNotesPlacement.name,
  }) {
    config.value = SiteConfig(
      emojiEnabled: false,
      plugins: PluginData.none.withValue(
        userNotesSettingsKey,
        UserNotesSettings(enabled: enabled, placement: placement),
      ),
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    config.dispose();
    await cooker.dispose();
    await installed.close();
  }
}

final class NotesFreshAccount implements PluginFreshAccountHost {
  bool staff = true;
  @override
  PluginFreshAccountProfile? profileFor(String siteUrl) =>
      PluginFreshAccountProfile(staff: staff, groups: const []);
  @override
  T? recordFor<T extends Object>(String siteUrl, PluginDataKey<T> key) => null;
}
